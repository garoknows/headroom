import Darwin
import Foundation

/// Where Codex keeps its files. Wiggleroom only ever reads `sessions/`, read-only.
public struct CodexPaths: Sendable {
    public let home: URL
    public init(home: URL) { self.home = home }

    public var codexFolder: URL { home.appendingPathComponent(".codex", isDirectory: true) }
    public var sessionsFolder: URL { codexFolder.appendingPathComponent("sessions", isDirectory: true) }
}

/// What the Codex reader found. Only states and numbers: never any text from Codex's files.
public enum CodexStatus: Equatable, Sendable {
    /// No `~/.codex` folder.
    case notInstalled
    /// Codex is installed but has no session files from the last 7 days.
    case noSessions
    /// Session files exist but none has a usage event yet (Codex hasn't replied since).
    case waitingForReply
    /// Codex replied but reports no plan limits (signed in with an API key, not ChatGPT).
    case noPlanLimits
    /// Usage events are there but their shape isn't one Wiggleroom understands.
    case formatChanged
    /// Numbers read.
    case ok
}

public struct CodexReading: Equatable, Sendable {
    public var status: CodexStatus
    public var usage: UsageSnapshot?

    public init(status: CodexStatus, usage: UsageSnapshot? = nil) {
        self.status = status
        self.usage = usage
    }
}

/// Reads Codex's plan limits from the end of its newest session log ("rollout file"), the same
/// numbers Codex shows in its own limits display. A rollout file is the user's whole conversation,
/// so (PRD section 2):
/// - only plain `rollout-*.jsonl` files from the last 7 days are opened, read-only, never locked;
/// - only the last 256 KB of a file is read ("tail read");
/// - a line is parsed only if it mentions `token_count`, and is dropped unless it is an
///   `event_msg` whose `payload.type` is `token_count`;
/// - from such a line only the limits' numbers and the line's time are copied out;
/// - nothing else from the files is kept, logged, printed or written, even on errors.
public enum CodexReader {
    public static let tailBytes = 256 * 1024
    public static let lookBack: TimeInterval = 7 * 24 * 3600
    /// At most this many files are opened per read (several Codex windows at once).
    static let maxFiles = 24

    public static func read(paths: CodexPaths, now: Date = Date()) -> CodexReading {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: paths.codexFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return CodexReading(status: .notInstalled)
        }
        let files = candidateFiles(in: paths.sessionsFolder, now: now)
        guard !files.isEmpty else { return CodexReading(status: .noSessions) }

        var best: Event?
        for (url, modified) in files.prefix(maxFiles) {
            // A file last changed before the best event so far can't hold a newer one.
            if let best, modified < best.timestamp.addingTimeInterval(-60) { break }
            guard let tail = readTail(url, bytes: tailBytes), let e = latestEvent(in: tail) else { continue }
            if best == nil || e.timestamp > best!.timestamp { best = e }
        }
        guard let best else { return CodexReading(status: .waitingForReply) }
        switch best.limits {
        case .absent:
            return CodexReading(status: .noPlanLimits)
        case .unreadable:
            return CodexReading(status: .formatChanged)
        case .windows(let windows):
            let usage = UsageSnapshot(updatedAt: min(best.timestamp, now), limits: LimitKind.sorted(windows))
            return CodexReading(status: .ok, usage: usage)
        }
    }

    // MARK: Finding the files

    /// Plain `rollout-*.jsonl` files changed in the last 7 days, newest first. Codex files a
    /// session under the `YYYY/MM/DD` folder of the day it *started*, and a resumed session keeps
    /// writing there weeks later, so every date folder is looked at and files are judged by when
    /// they were last written (only folder listings and file dates; no file is opened here).
    /// Loose files directly in `sessions/` (older Codex versions) count too. Symlinks are skipped.
    static func candidateFiles(in sessions: URL, now: Date) -> [(URL, Date)] {
        let fm = FileManager.default
        let oldest = now.addingTimeInterval(-lookBack)
        var folders: [URL] = [sessions]
        for year in subfolders(sessions, digits: 4) {
            for month in subfolders(year, digits: 2) {
                folders += subfolders(month, digits: 2)
            }
        }
        var out: [(URL, Date)] = []
        for folder in folders {
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasPrefix("rollout-") && name.hasSuffix(".jsonl") {
                let url = folder.appendingPathComponent(name)
                var st = stat()
                guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
                let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                if modified >= oldest { out.append((url, modified)) }
            }
        }
        return out.sorted { $0.1 > $1.1 }
    }

    static func subfolders(_ url: URL, digits: Int) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.count == digits && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
            .sorted(by: >)
            .map { url.appendingPathComponent($0, isDirectory: true) }
    }

    // MARK: Reading the end of one file

    /// The last `bytes` of a regular file, opened read-only without following a symlink.
    /// Codex may still be writing it; nothing is locked.
    static func readTail(_ url: URL, bytes: Int) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let size = Int(st.st_size)
        let start = max(0, size - bytes)
        let length = size - start
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let got = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, length, off_t(start)) }
        guard got > 0 else { return nil }
        data.count = got
        // Starting mid-file: the first line is cut, so drop it.
        if start > 0, let nl = data.firstIndex(of: 0x0A) { data = data.subdata(in: data.index(after: nl)..<data.endIndex) }
        return data
    }

    // MARK: Picking the usage events out

    enum Limits: Equatable {
        /// No `rate_limits`, or no windows in it (a plan without limits).
        case absent
        /// Windows are there, but none could be read.
        case unreadable
        case windows([LimitWindow])
    }

    struct Event: Equatable {
        var timestamp: Date
        var limits: Limits
    }

    static let marker = Data(#""token_count""#.utf8)

    /// The newest usage event in a chunk of a log. Lines that don't mention `token_count` are
    /// never parsed; a line that doesn't parse (half-written) is skipped.
    static func latestEvent(in data: Data) -> Event? {
        var best: Event?
        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            let lineEnd = data[lineStart...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[lineStart..<lineEnd]
            lineStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
            guard line.range(of: marker) != nil, let e = event(fromLine: Data(line)) else { continue }
            if best == nil || e.timestamp >= best!.timestamp { best = e }
        }
        return best
    }

    /// One line: kept only if it is an `event_msg` whose `payload.type` is `token_count`, and
    /// then only its time and the limits' numbers come out.
    static func event(fromLine line: Data) -> Event? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "event_msg",
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let timestamp = date(obj["timestamp"]) else { return nil }
        return Event(timestamp: timestamp, limits: limits(payload["rate_limits"], at: timestamp))
    }

    static func limits(_ value: Any?, at timestamp: Date) -> Limits {
        guard let rl = value as? [String: Any] else { return .absent }
        // A window is any object in `rate_limits` that looks like one (primary, secondary and
        // any Codex adds later). Other fields (credits, plan names) are never looked at.
        let candidates = rl.keys.sorted().compactMap { key -> [String: Any]? in
            guard let w = rl[key] as? [String: Any], key != "credits" else { return nil }
            return w
        }
        guard !candidates.isEmpty else { return .absent }
        var out: [LimitWindow] = []
        var ids = Set<String>()
        for w in candidates {
            guard let minutes = number(w["window_minutes"]).map({ Int($0.rounded()) }), minutes > 0,
                  let pct = number(w["used_percent"]), pct.isFinite else { continue }
            let id = WindowNaming.id(windowMinutes: minutes)
            guard ids.insert(id).inserted else { continue }
            let clamped = min(100, max(0, pct))
            out.append(LimitWindow(id: id, usedPercent: clamped, outOfRange: clamped != pct,
                                   resetsAt: resetTime(w, at: timestamp), label: WindowNaming.label(windowMinutes: minutes),
                                   windowMinutes: minutes))
        }
        return out.isEmpty ? .unreadable : .windows(out)
    }

    /// `resets_at` (Unix seconds, or milliseconds) wins; otherwise the event's time plus
    /// `resets_in_seconds`. Anything negative, absurd or not a number means "unknown".
    static func resetTime(_ w: [String: Any], at timestamp: Date) -> Date? {
        if let at = number(w["resets_at"]) {
            let seconds = at > 1e12 ? at / 1000 : at
            let d = Date(timeIntervalSince1970: seconds)
            return RateLimitParser.plausibleDates.contains(d) ? d : nil
        }
        if let s = number(w["resets_in_seconds"]), s >= 0, s <= 400 * 86400 {
            return timestamp.addingTimeInterval(s)
        }
        return nil
    }

    /// A number given as a JSON number or as a numeric string.
    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = v as? String, s.count <= 32, let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite { return d }
        return nil
    }

    static func date(_ v: Any?) -> Date? {
        if let s = v as? String, s.count <= 40 {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        }
        if let n = number(v) { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        return nil
    }
}

/// Keeps Codex's last good numbers in Wiggleroom's own private folder (0600, atomic).
public enum CodexStore {
    public static func save(_ usage: UsageSnapshot, paths: WiggleroomPaths) throws {
        try SecureFile.ensurePrivateFolder(paths.supportFolder)
        try SecureFile.atomicWrite(try usage.encoded(), to: paths.codexFile, mode: 0o600)
    }

    public static func load(paths: WiggleroomPaths, now: Date = Date()) -> UsageSnapshot? {
        SecureFile.readSmallFile(paths.codexFile).flatMap(UsageSnapshot.decode).flatMap {
            SnapshotPolicy.isPlausible($0, now: now) ? $0 : nil
        }
    }

    public static func remove(paths: WiggleroomPaths) {
        try? FileManager.default.removeItem(at: paths.codexFile)
    }
}

/// What the Codex row in Settings says.
public enum CodexStatusText {
    public static let notFound = "Codex not found on this Mac"
    public static let waiting = "Connected. Your numbers appear after Codex's next reply."
    public static let noPlanLimits = "Codex isn't reporting plan limits (are you signed in with ChatGPT?)"
    public static let formatChanged = "Codex changed its log format; Wiggleroom needs an update"

    public static func text(connected: Bool, installed: Bool, status: CodexStatus, watching: Bool, hasNumbers: Bool) -> String {
        guard installed, status != .notInstalled else { return notFound }
        guard connected else { return "Not connected" }
        switch status {
        case .ok: return watching ? "Connected" : "Connected, but not watching. Click Check Again."
        case .noPlanLimits: return noPlanLimits
        case .formatChanged: return formatChanged
        case .noSessions, .waitingForReply: return hasNumbers ? "Connected" : waiting
        case .notInstalled: return notFound
        }
    }
}
