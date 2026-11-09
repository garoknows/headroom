import Darwin
import Foundation

/// Where Headroom keeps its files. Everything is under one folder named after the app's
/// bundle ID, so it can never clash with another app's folder (DECISIONS D6).
public struct HeadroomPaths: Sendable {
    public static let folderName = "io.github.garoknows.headroom"

    public let home: URL

    public init(home: URL) { self.home = home }

    /// The real user's home folder. Uses HOME when set (that's what Claude Code passes on),
    /// otherwise the account's home from the system.
    public static func currentUser() -> HeadroomPaths {
        if let h = ProcessInfo.processInfo.environment["HOME"], h.hasPrefix("/") {
            return HeadroomPaths(home: URL(fileURLWithPath: h, isDirectory: true))
        }
        return HeadroomPaths(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var supportFolder: URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(Self.folderName, isDirectory: true)
    }
    /// The numbers the status line script writes. Only `rate_limits` and the time.
    public var usageFile: URL { supportFolder.appendingPathComponent("usage.json") }
    public var lockFile: URL { supportFolder.appendingPathComponent(".usage.lock") }
    public var backupFolder: URL { supportFolder.appendingPathComponent("settings-backups", isDirectory: true) }
    /// Claude Code's user settings file.
    public var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
}

public enum SecureFileError: Error, Equatable {
    case cannotCreateFolder(Int32)
    case cannotWrite(Int32)
    case cannotRename(Int32)
}

/// Private, all-or-nothing file writes.
public enum SecureFile {
    /// Creates `folder` (and parents) if needed and makes sure only this user can open it (0700).
    public static func ensurePrivateFolder(_ folder: URL) throws {
        let path = folder.path
        var st = stat()
        if lstat(path, &st) != 0 {
            try? FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            if mkdir(path, 0o700) != 0 && errno != EEXIST { throw SecureFileError.cannotCreateFolder(errno) }
            guard lstat(path, &st) == 0 else { throw SecureFileError.cannotCreateFolder(errno) }
        }
        // Refuse a symlink or a plain file where the folder should be.
        guard (st.st_mode & S_IFMT) == S_IFDIR else { throw SecureFileError.cannotCreateFolder(ENOTDIR) }
        if (st.st_mode & 0o777) != 0o700 { chmod(path, 0o700) }
    }

    /// Writes `data` to a new temporary file next to `url` with permissions `mode`, then renames
    /// it over `url`. Readers see either the old file or the new one, never half of one, even if
    /// this process is stopped in the middle (Claude Code cancels a status line that runs long).
    public static func atomicWrite(_ data: Data, to url: URL, mode: mode_t = 0o600) throws {
        let dir = url.deletingLastPathComponent().path
        let tmp = "\(dir)/.\(url.lastPathComponent).\(getpid()).\(UInt32.random(in: 0...UInt32.max)).tmp"
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode)
        guard fd >= 0 else { throw SecureFileError.cannotWrite(errno) }
        // open() applies the umask; set the exact mode explicitly.
        fchmod(fd, mode)
        var ok = true
        data.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n <= 0 { if n < 0 && errno == EINTR { continue }; ok = false; break }
                offset += n
            }
        }
        if ok && fsync(fd) != 0 { ok = false }
        close(fd)
        guard ok else { unlink(tmp); throw SecureFileError.cannotWrite(errno) }
        if rename(tmp, url.path) != 0 {
            let e = errno
            unlink(tmp)
            throw SecureFileError.cannotRename(e)
        }
    }

    /// Reads a small regular file (refusing symlinks and anything over `limit` bytes).
    public static func readSmallFile(_ url: URL, limit: Int = 256 * 1024) -> Data? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= limit else { return nil }
        var data = Data(count: Int(st.st_size))
        let n = data.withUnsafeMutableBytes { read(fd, $0.baseAddress, Int(st.st_size)) }
        return n == Int(st.st_size) ? data : nil
    }

    /// Takes an exclusive lock on `url`, trying for at most `budget` seconds.
    /// Returns the open descriptor (close it to unlock), or nil if the lock wasn't free in time.
    public static func lock(_ url: URL, budget: TimeInterval) -> Int32? {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return nil }
        let deadline = Date().addingTimeInterval(budget)
        while true {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
            if Date() >= deadline { close(fd); return nil }
            usleep(1000)
        }
    }

    /// Removes temp files a cancelled write left behind (Claude Code stops the status line
    /// program if a newer update arrives, which can happen between writing and renaming).
    /// Only Headroom's own ".usage.json.<pid>.<random>.tmp" names, and only old ones.
    public static func removeStaleTempFiles(in folder: URL, olderThan age: TimeInterval, now: Date = Date()) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(".usage.json.") && name.hasSuffix(".tmp") {
            let path = folder.appendingPathComponent(name).path
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            if now.timeIntervalSince1970 - Double(st.st_mtimespec.tv_sec) > age { unlink(path) }
        }
    }

    /// Permission bits of a file (for example 0o600), or nil if it can't be read.
    public static func permissions(of url: URL) -> mode_t? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return st.st_mode & 0o777
    }
}
