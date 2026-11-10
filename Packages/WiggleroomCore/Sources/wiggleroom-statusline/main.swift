// wiggleroom-statusline: the tiny command Claude Code runs on every status line update.
//
// 1. Reads the JSON Claude Code sends on standard input.
// 2. Starts the user's previous status line command (if any) with the same input, so its
//    output goes straight to Claude Code, unchanged.
// 3. Meanwhile keeps only `rate_limits` and the time, and saves them (0600, atomic write).
// 4. Waits for the previous command and exits with its exit code, so Claude Code sees exactly
//    what it saw before Wiggleroom.
//
// Any problem in Wiggleroom's own part is swallowed: the status line must never break.
// No network code, no Keychain, no other files.

import Darwin
import Foundation
import WiggleroomCore

signal(SIGPIPE, SIG_IGN)

nonisolated(unsafe) var childPID: pid_t = 0

/// If Claude Code cancels us (a newer update arrived), stop the previous command too.
func forwardAndExit(_ sig: Int32) {
    if childPID > 0 { kill(childPID, sig) }
    _exit(128 + sig)
}
signal(SIGTERM, forwardAndExit)
signal(SIGINT, forwardAndExit)
signal(SIGHUP, forwardAndExit)

let input = FileHandle.standardInput.readDataToEndOfFile()

// The previous command, from `--then <base64>`. A malformed value means "no previous command".
var previous: String?
let args = CommandLine.arguments
if let i = args.firstIndex(of: StatuslineCommand.thenFlag), i + 1 < args.count {
    previous = StatuslineCommand.decodePrevious(args[i + 1])
}

/// Starts `/bin/sh -c <command>` with a pipe on standard input; output goes straight through.
func startPrevious(_ command: String) -> (pid: pid_t, stdinWrite: Int32)? {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return nil }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, fds[0], 0)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_addclose(&actions, fds[1])
    // The previous command must start exactly as Claude Code would start it: with every signal
    // at its default. Wiggleroom ignores SIGPIPE for itself, and an ignored signal would otherwise
    // be inherited (then `yes | head -1` would print "Broken pipe" errors and change exit codes).
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    var defaults = sigset_t([SIGPIPE, SIGTERM, SIGINT, SIGHUP].reduce(UInt32(0)) { $0 | (1 << UInt32($1 - 1)) })
    var noMask = sigset_t(0)
    posix_spawnattr_setsigdefault(&attr, &defaults)
    posix_spawnattr_setsigmask(&attr, &noMask)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(command), nil]
    defer { argv.forEach { free($0) } }
    let rc = posix_spawn(&pid, "/bin/sh", &actions, &attr, argv, environ)
    close(fds[0])
    guard rc == 0 else { close(fds[1]); return nil }
    return (pid, fds[1])
}

var feeder: Thread?
if let previous, let child = startPrevious(previous) {
    childPID = child.pid
    // Feed the input on another thread so a command that reads slowly (or not at all) can't
    // hold up saving the numbers.
    let fd = child.stdinWrite
    let payload = input
    let t = Thread {
        payload.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                off += n
            }
        }
        close(fd)
    }
    t.start()
    feeder = t
}

// Wiggleroom's own part. Never throws, never prints.
StatuslineRecorder.record(payload: input, paths: WiggleroomPaths.currentUser())

guard childPID > 0 else { exit(0) }
var status: Int32 = 0
while waitpid(childPID, &status, 0) < 0 && errno == EINTR {}
let exited = (status & 0x7F) == 0
exit(exited ? (status >> 8) & 0xFF : 128 + (status & 0x7F))
