import Darwin
import Foundation
import HeadroomCore
import Testing

/// Runs the real `headroom-statusline` program the way Claude Code does: JSON on standard input,
/// the output read back from standard output. Each test uses its own temp home folder.
@Suite(.serialized) struct StatuslineEndToEndTests {

    static let binary: URL? = {
        if let p = ProcessInfo.processInfo.environment["HEADROOM_STATUSLINE_BIN"] { return URL(fileURLWithPath: p) }
        // `swift test`: the program sits next to the test bundle in the build folder.
        for b in Bundle.allBundles where b.bundleURL.pathExtension == "xctest" {
            let candidate = b.bundleURL.deletingLastPathComponent().appendingPathComponent("headroom-statusline")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        // Otherwise look in the package's own build folder for the newest copy.
        let build = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build")
        let found = FileManager.default.enumerator(at: build, includingPropertiesForKeys: [.contentModificationDateKey])?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "headroom-statusline" && FileManager.default.isExecutableFile(atPath: $0.path) && !$0.path.contains(".dSYM") }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
        return found
    }()

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("HeadroomCoreTests/Fixtures")
    static func fixture(_ name: String) -> Data { FileManager.default.contents(atPath: fixtures.appendingPathComponent(name).path)! }

    static func tempHome() -> URL {
        let root = ProcessInfo.processInfo.environment["HEADROOM_TEST_TMP"] ?? NSTemporaryDirectory()
        let u = URL(fileURLWithPath: root).appendingPathComponent("hr-e2e-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    struct Run { var out: Data; var err: Data; var status: Int32; var seconds: Double }

    /// Runs `executable args` with `input` on stdin and HOME set to `home`.
    static func run(_ executable: String, _ args: [String], input: Data, home: URL, extraEnv: [String: String] = [:]) throws -> Run {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        env["COLUMNS"] = "97"
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        let start = DispatchTime.now()
        try p.run()
        DispatchQueue.global().async {
            try? inPipe.fileHandleForWriting.write(contentsOf: input)
            try? inPipe.fileHandleForWriting.close()
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let secs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        return Run(out: out, err: err, status: p.terminationStatus, seconds: secs)
    }

    static func headroom(_ previous: String?, input: Data, home: URL) throws -> Run {
        let bin = try #require(binary, "headroom-statusline wasn't built")
        var args: [String] = []
        if let previous { args = [StatuslineCommand.thenFlag, Data(previous.utf8).base64EncodedString()] }
        return try run(bin.path, args, input: input, home: home)
    }

    /// The previous command run by itself, the way Claude Code runs it. Foundation's Process
    /// rewrites accented letters in arguments (é becomes e plus an accent mark), so the command
    /// is handed over in base64 and decoded by the shell, keeping its exact bytes.
    static func direct(_ command: String, input: Data, home: URL) throws -> Run {
        let b64 = Data(command.utf8).base64EncodedString()
        return try run("/bin/sh", ["-c", "exec /bin/sh -c \"$(printf %s \(b64) | /usr/bin/base64 -D)\""], input: input, home: home)
    }

    static func usageFile(_ home: URL) -> URL { HeadroomPaths(home: home).usageFile }

    // MARK: Tests

    @Test func binaryIsAvailable() {
        #expect(Self.binary != nil, "build headroom-statusline before running these tests")
    }

    @Test func savesOnlyTheLimitsPrivatelyAndPrintsNothing() throws {
        let home = Self.tempHome()
        let r = try Self.headroom(nil, input: Self.fixture("full-payload.json"), home: home)
        #expect(r.status == 0)
        #expect(r.out.isEmpty && r.err.isEmpty)
        let data = try #require(FileManager.default.contents(atPath: Self.usageFile(home).path))
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(top.keys) == UsageSnapshot.allowedKeys)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.lowercased().contains("secret") && !text.contains("private/var"))
        #expect(SecureFile.permissions(of: Self.usageFile(home)) == 0o600)
        #expect(SecureFile.permissions(of: HeadroomPaths(home: home).supportFolder) == 0o700)
    }

    /// The user's status line must look exactly the same with Headroom in front of it.
    @Test(arguments: [
        "shasum -a 256",
        "printf 'width=%s\\n' \"$COLUMNS\"; wc -c | tr -d ' '",
        "printf '\\033[32m%s\\033[0m ✓ émoji 🚀\\n' line1; printf 'second line\\n'",
        "cat",
        "echo partial; exit 3",
        "echo 'to stderr' >&2; echo out",
        "exit 0",
        "true | false",
        "yes | head -1",
        "set -o pipefail; yes | head -2; echo \"exit=$?\"",
    ])
    func passThroughIsIdentical(previous: String) throws {
        let home = Self.tempHome()
        let input = Self.fixture("full-payload.json")
        let without = try Self.direct(previous, input: input, home: home)
        let with = try Self.headroom(previous, input: input, home: home)
        #expect(with.out == without.out, "with: \(String(decoding: with.out, as: UTF8.self).debugDescription) without: \(String(decoding: without.out, as: UTF8.self).debugDescription)")
        #expect(with.err == without.err)
        #expect(with.status == without.status)
        // ...and the numbers were still saved, even when the previous command failed.
        #expect(FileManager.default.fileExists(atPath: Self.usageFile(home).path))
    }

    /// If Headroom is deleted without disconnecting, the saved command falls back to running
    /// the previous status line by itself, so Claude Code still shows it.
    @Test func commandFallsBackWhenHeadroomIsGone() throws {
        let home = Self.tempHome()
        let input = Self.fixture("full-payload.json")
        let previous = "printf 'mine: %s\\n' \"$(wc -c | tr -d ' ')\""
        let gone = StatuslineCommand(executablePath: "/nonexistent/Headroom.app/Contents/MacOS/headroom-statusline", previous: previous)
        let viaFallback = try Self.direct(gone.commandLine, input: input, home: home)
        let alone = try Self.direct(previous, input: input, home: home)
        #expect(viaFallback.out == alone.out && viaFallback.status == alone.status)
        #expect(!viaFallback.out.isEmpty)
        // And with Headroom present, the same command line runs Headroom (which saves numbers).
        let bin = try #require(Self.binary)
        let present = StatuslineCommand(executablePath: bin.path, previous: previous)
        let viaHeadroom = try Self.direct(present.commandLine, input: input, home: home)
        #expect(viaHeadroom.out == alone.out)
        #expect(FileManager.default.fileExists(atPath: Self.usageFile(home).path))
        // No previous command and no Headroom: nothing printed, no error.
        let bare = try Self.direct(StatuslineCommand(executablePath: "/nonexistent/headroom-statusline", previous: nil).commandLine, input: input, home: home)
        #expect(bare.out.isEmpty && bare.err.isEmpty && bare.status == 0)
    }

    @Test func numbersAreSavedBeforeASlowStatusLineFinishes() throws {
        let home = Self.tempHome()
        let bin = try #require(Self.binary)
        let p = Process()
        p.executableURL = bin
        p.arguments = [StatuslineCommand.thenFlag, Data("sleep 1.5; echo done".utf8).base64EncodedString()]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe
        try p.run()
        try inPipe.fileHandleForWriting.write(contentsOf: Self.fixture("full-payload.json"))
        try inPipe.fileHandleForWriting.close()
        var savedWhileRunning = false
        for _ in 0..<50 {
            usleep(10_000)
            if FileManager.default.fileExists(atPath: Self.usageFile(home).path) { savedWhileRunning = p.isRunning; break }
        }
        #expect(savedWhileRunning)
        p.waitUntilExit()
        #expect(String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "done\n")
    }

    @Test func cancelStopsPromptly() throws {
        // Claude Code cancels a status line that is still running when a newer update arrives.
        let home = Self.tempHome()
        let bin = try #require(Self.binary)
        let p = Process()
        p.executableURL = bin
        p.arguments = [StatuslineCommand.thenFlag, Data("sleep 10".utf8).base64EncodedString()]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let inPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = Pipe()
        try p.run()
        try inPipe.fileHandleForWriting.write(contentsOf: Self.fixture("full-payload.json"))
        try inPipe.fileHandleForWriting.close()
        usleep(200_000)
        let start = Date()
        p.terminate()
        p.waitUntilExit()
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(p.terminationReason == .exit && p.terminationStatus == 128 + SIGTERM)
    }

    @Test func noRateLimitsWritesNothingAndStillPassesThrough() throws {
        let home = Self.tempHome()
        let r = try Self.headroom("echo hello", input: Self.fixture("no-rate-limits.json"), home: home)
        #expect(String(decoding: r.out, as: UTF8.self) == "hello\n")
        #expect(r.status == 0)
        #expect(!FileManager.default.fileExists(atPath: HeadroomPaths(home: home).supportFolder.path))
    }

    @Test func garbageInputAndBrokenArgumentsNeverBreakTheStatusLine() throws {
        let home = Self.tempHome()
        let r = try Self.headroom("cat", input: Data("this is not JSON {{{".utf8), home: home)
        #expect(String(decoding: r.out, as: UTF8.self) == "this is not JSON {{{")
        #expect(r.status == 0)
        let bin = try #require(Self.binary)
        let bad = try Self.run(bin.path, ["--then", "%%%not-base64"], input: Self.fixture("full-payload.json"), home: home)
        #expect(bad.status == 0 && bad.out.isEmpty)
        let empty = try Self.run(bin.path, [], input: Data(), home: home)
        #expect(empty.status == 0 && empty.out.isEmpty)
    }

    @Test func unwritableHomeIsSwallowed() throws {
        let home = Self.tempHome()
        try Data("x".utf8).write(to: home.appendingPathComponent("Library"))  // a file where a folder should be
        let r = try Self.headroom("echo still works", input: Self.fixture("full-payload.json"), home: home)
        #expect(String(decoding: r.out, as: UTF8.self) == "still works\n")
        #expect(r.status == 0)
        #expect(r.err.isEmpty)
    }

    /// PRD section 7: the script must finish within 50 ms. Median of 25 runs, after one warm-up.
    @Test func runsInUnderFiftyMilliseconds() throws {
        let home = Self.tempHome()
        let input = Self.fixture("full-payload.json")
        _ = try Self.headroom(nil, input: input, home: home)
        var times: [Double] = []
        for _ in 0..<25 { times.append(try Self.headroom(nil, input: input, home: home).seconds) }
        times.sort()
        let median = times[times.count / 2]
        print("headroom-statusline median \(Int(median * 1000)) ms, fastest \(Int(times[0] * 1000)) ms, slowest \(Int(times.last! * 1000)) ms")
        #expect(median < 0.050)
    }

    /// Lesson 15: a huge payload (2 MB of path text) stays fast and small.
    @Test func largeInputStaysWithinBudget() throws {
        let home = Self.tempHome()
        var obj = try #require(try JSONSerialization.jsonObject(with: Self.fixture("full-payload.json")) as? [String: Any])
        obj["cwd"] = String(repeating: "/very-long-folder-name", count: 100_000)
        obj["extra"] = Array(repeating: ["a": 1, "b": "text"], count: 20_000)
        let big = try JSONSerialization.data(withJSONObject: obj)
        #expect(big.count > 2_000_000)
        var before = rusage(); getrusage(RUSAGE_CHILDREN, &before)
        let r = try Self.headroom("wc -c | tr -d ' '", input: big, home: home)
        var after = rusage(); getrusage(RUSAGE_CHILDREN, &after)
        #expect(String(decoding: r.out, as: UTF8.self) == "\(big.count)\n") // the previous command got all of it
        #expect(r.seconds < 0.5)
        // ru_maxrss is in bytes on macOS. The largest child so far must stay under 100 MB.
        #expect(after.ru_maxrss < 100 * 1024 * 1024)
        print("2 MB payload: \(Int(r.seconds * 1000)) ms, peak child memory \(after.ru_maxrss / 1024 / 1024) MB")
        let data = try #require(FileManager.default.contents(atPath: Self.usageFile(home).path))
        #expect(!String(decoding: data, as: UTF8.self).contains("very-long-folder-name"))
    }

    @Test func twoSessionsAtOnceLeaveOneValidFile() async throws {
        let home = Self.tempHome()
        let input = Self.fixture("full-payload.json")
        try await withThrowingTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { _ = try Self.headroom("cat > /dev/null", input: input, home: home) } }
            try await g.waitForAll()
        }
        let s = try #require(SecureFile.readSmallFile(Self.usageFile(home)).flatMap(UsageSnapshot.decode))
        #expect(s.limits.count == 3)
        let names = try FileManager.default.contentsOfDirectory(atPath: HeadroomPaths(home: home).supportFolder.path)
        #expect(Set(names) == ["usage.json", ".usage.lock"])
    }
}
