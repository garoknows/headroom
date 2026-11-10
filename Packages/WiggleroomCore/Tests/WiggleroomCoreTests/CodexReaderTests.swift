import Darwin
import Foundation
import Testing
@testable import WiggleroomCore

/// The Codex reader, on invented session logs only (never real ones). Each file is built here in
/// a temporary home folder, in the shape Codex uses: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`,
/// one JSON object per line.
@Suite struct CodexReaderTests {
    // Thursday Jan 14, 2027, 2:45 PM in Las Vegas (22:45 UTC).
    let now = date(2027, 1, 14, 14, 45, tz: vegas)

    // MARK: Invented log lines

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    /// A usage event, in the shape Codex writes (with fields Wiggleroom must ignore).
    static func tokenCount(at t: Date, rateLimits: String) -> String {
        #"{"timestamp":"\#(iso(t))","ordinal":7,"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":12,"output_tokens":3,"total_tokens":15},"model_context_window":200000},"rate_limits":\#(rateLimits)}}"#
    }

    static func limits(primary: String = #"{"used_percent":12.5,"window_minutes":300,"resets_at":1800026400}"#,
                       secondary: String = #"{"used_percent":41.2,"window_minutes":10080,"resets_at":1800403200}"#,
                       extra: String = "") -> String {
        #"{"primary":\#(primary),"secondary":\#(secondary),"credits":{"balance":"0","has_credits":false,"unlimited":false},"plan_type":"plus","limit_id":"codex","limit_name":null,"individual_limit":null,"rate_limit_reached_type":null,"spend_control_reached":null\#(extra)}"#
    }

    static let chatter = [
        #"{"timestamp":"2027-01-14T22:30:00.000Z","ordinal":1,"type":"session_meta","payload":{"cwd":"/tmp/invented-project","model":"invented"}}"#,
        #"{"timestamp":"2027-01-14T22:31:00.000Z","ordinal":2,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Please fix the build"}]}}"#,
    ]

    // MARK: Building a temporary Codex folder

    struct CodexHome {
        let home: URL
        var paths: CodexPaths { CodexPaths(home: home) }

        init(installed: Bool = true, sessions: Bool = true) {
            home = makeTempHome()
            if installed { try! FileManager.default.createDirectory(at: paths.codexFolder, withIntermediateDirectories: true) }
            if sessions { try! FileManager.default.createDirectory(at: paths.sessionsFolder, withIntermediateDirectories: true) }
        }

        /// Writes a rollout file in the `YYYY/MM/DD` folder for `day` (Codex uses local dates).
        @discardableResult
        func rollout(_ lines: [String], day: Date, name: String = "rollout-2027-01-14T22-30-00-0000.jsonl",
                     modified: Date? = nil, trailingNewline: Bool = true, tz: String = vegas) -> URL {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: tz)!
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let folder = paths.sessionsFolder
                .appendingPathComponent(String(format: "%04d", c.year!))
                .appendingPathComponent(String(format: "%02d", c.month!))
                .appendingPathComponent(String(format: "%02d", c.day!))
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
            try! Data(text.utf8).write(to: url)
            if let modified { try! FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
            return url
        }
    }

    func read(_ h: CodexHome) -> CodexReading { CodexReader.read(paths: h.paths, now: now) }

    // MARK: Installed or not

    @Test func notInstalled() {
        #expect(read(CodexHome(installed: false, sessions: false)).status == .notInstalled)
    }

    @Test func installedButNeverRun() {
        #expect(read(CodexHome(installed: true, sessions: false)).status == .noSessions)
        #expect(read(CodexHome(installed: true, sessions: true)).status == .noSessions)   // empty sessions folder
    }

    @Test func sessionWithoutAReplyYet() {
        let h = CodexHome()
        h.rollout(Self.chatter, day: now, modified: now)
        #expect(read(h).status == .waitingForReply)
    }

    // MARK: Reading the numbers

    @Test func readsBothWindowsWithLabelsAndAbsoluteResets() throws {
        let h = CodexHome()
        let t = now.addingTimeInterval(-90)
        h.rollout(Self.chatter + [Self.tokenCount(at: t, rateLimits: Self.limits())], day: now, modified: now)
        let r = read(h)
        #expect(r.status == .ok)
        let u = try #require(r.usage)
        #expect(abs(u.updatedAt.timeIntervalSince(t)) < 0.01)
        #expect(u.limits.map(\.id) == ["five_hour", "seven_day"])
        #expect(u.limits.map(\.label) == ["5-hour", "This week"])
        #expect(u.limits.map(\.windowMinutes) == [300, 10080])
        #expect(u.limit("five_hour")?.usedPercent == 12.5)
        #expect(u.limit("seven_day")?.usedPercent == 41.2)
        #expect(u.limit("seven_day")?.resetsAt == Date(timeIntervalSince1970: 1_800_403_200))
    }

    @Test func resetsAtInMillisecondsAndResetsInSeconds() throws {
        let h = CodexHome()
        let t = now.addingTimeInterval(-60)
        let ms = Self.limits(primary: #"{"used_percent":5,"window_minutes":300,"resets_at":1800026400000}"#,
                             secondary: #"{"used_percent":6,"window_minutes":10080,"resets_in_seconds":7200}"#)
        h.rollout([Self.tokenCount(at: t, rateLimits: ms)], day: now, modified: now)
        let u = try #require(read(h).usage)
        #expect(u.limit("five_hour")?.resetsAt == Date(timeIntervalSince1970: 1_800_026_400))
        #expect(u.limit("seven_day")?.resetsAt.map { abs($0.timeIntervalSince(t.addingTimeInterval(7200))) < 0.01 } == true)
    }

    @Test func resetsAtIsPreferredOverResetsInSeconds() throws {
        let h = CodexHome()
        let both = Self.limits(primary: #"{"used_percent":5,"window_minutes":300,"resets_at":1800026400,"resets_in_seconds":99}"#)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: both)], day: now, modified: now)
        #expect(try #require(read(h).usage).limit("five_hour")?.resetsAt == Date(timeIntervalSince1970: 1_800_026_400))
    }

    @Test(arguments: [#""resets_in_seconds":-30"#, #""resets_in_seconds":99999999999"#, #""resets_in_seconds":"soon""#, #""other":1"#])
    func oddResetTimesBecomeUnknownButThePercentStays(reset: String) throws {
        let h = CodexHome()
        let odd = Self.limits(primary: #"{"used_percent":5,"window_minutes":300,\#(reset)}"#)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: odd)], day: now, modified: now)
        let u = try #require(read(h).usage)
        #expect(u.limit("five_hour")?.usedPercent == 5)
        #expect(u.limit("five_hour")?.resetsAt == nil)
    }

    @Test(arguments: [("12", 12.0), ("12.75", 12.75), (#""33.5""#, 33.5), ("140", 100.0), ("-3", 0.0)])
    func percentAsIntegerFloatOrString(value: String, expected: Double) throws {
        let h = CodexHome()
        let l = Self.limits(primary: #"{"used_percent":\#(value),"window_minutes":300,"resets_at":1800026400}"#)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: l)], day: now, modified: now)
        #expect(try #require(read(h).usage).limit("five_hour")?.usedPercent == expected)
    }

    @Test func aWindowWithAnUnreadablePercentIsLeftOut() throws {
        let h = CodexHome()
        let l = Self.limits(primary: #"{"used_percent":"lots","window_minutes":300,"resets_at":1800026400}"#)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: l)], day: now, modified: now)
        let u = try #require(read(h).usage)
        #expect(u.limits.map(\.id) == ["seven_day"])
    }

    /// Never assume primary is the 5-hour window, and keep windows Codex may add later.
    @Test func windowsAreNamedByLengthNotPosition() throws {
        let h = CodexHome()
        let l = Self.limits(primary: #"{"used_percent":40,"window_minutes":10080,"resets_at":1800403200}"#,
                            secondary: #"{"used_percent":9,"window_minutes":300,"resets_at":1800026400}"#,
                            extra: #","tertiary":{"used_percent":2,"window_minutes":1440,"resets_at":1800100000}"#)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: l)], day: now, modified: now)
        let u = try #require(read(h).usage)
        #expect(u.limit("seven_day")?.usedPercent == 40)
        #expect(u.limit("five_hour")?.usedPercent == 9)
        #expect(u.limit("window_1440")?.label == "1-day")
    }

    // MARK: Files being written, several sessions, dates

    /// Codex is still writing its last line: skip it and use the event before. Never crash.
    @Test func halfWrittenLastLineIsSkipped() throws {
        let h = CodexHome()
        let earlier = Self.tokenCount(at: now.addingTimeInterval(-120), rateLimits: Self.limits())
        let newer = Self.tokenCount(at: now.addingTimeInterval(-10), rateLimits: Self.limits(secondary: #"{"used_percent":77,"window_minutes":10080,"resets_at":1800403200}"#))
        h.rollout([earlier, String(newer.prefix(newer.count / 2))], day: now, modified: now, trailingNewline: false)
        let u = try #require(read(h).usage)
        #expect(u.limit("seven_day")?.usedPercent == 41.2)
    }

    /// Two Codex windows at once: the newest event wins, whichever file was touched last.
    @Test func newestEventWinsAcrossSessions() throws {
        let h = CodexHome()
        let older = Self.tokenCount(at: now.addingTimeInterval(-600), rateLimits: Self.limits(secondary: #"{"used_percent":20,"window_minutes":10080,"resets_at":1800403200}"#))
        let newer = Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: Self.limits(secondary: #"{"used_percent":55,"window_minutes":10080,"resets_at":1800403200}"#))
        h.rollout([newer], day: now, name: "rollout-a.jsonl", modified: now.addingTimeInterval(-30))
        h.rollout([older] + Self.chatter, day: now, name: "rollout-b.jsonl", modified: now)   // touched later, older event
        #expect(try #require(read(h).usage).limit("seven_day")?.usedPercent == 55)
    }

    /// Late in the evening, the newest session can sit in tomorrow's folder.
    @Test func newestFileInTomorrowsFolder() throws {
        let late = date(2027, 1, 14, 23, 50, tz: vegas)
        let h = CodexHome()
        h.rollout([Self.tokenCount(at: late.addingTimeInterval(-60), rateLimits: Self.limits())], day: late.addingTimeInterval(86400), modified: late)
        #expect(CodexReader.read(paths: h.paths, now: late).status == .ok)
    }

    /// Older files are used only when the newest has no usage event yet, up to 7 days back.
    @Test func olderFilesOnlyWithinSevenDays() throws {
        let h = CodexHome()
        let threeDays = now.addingTimeInterval(-3 * 86400)
        h.rollout([Self.tokenCount(at: threeDays, rateLimits: Self.limits())], day: threeDays, name: "rollout-old.jsonl", modified: threeDays)
        h.rollout(Self.chatter, day: now, name: "rollout-new.jsonl", modified: now)
        #expect(read(h).status == .ok)

        let h2 = CodexHome()
        let nineDays = now.addingTimeInterval(-9 * 86400)
        h2.rollout([Self.tokenCount(at: nineDays, rateLimits: Self.limits())], day: nineDays, modified: nineDays)
        #expect(read(h2).status == .noSessions)
    }

    /// Finished sessions that Codex compressed (`.jsonl.zst`) are never opened (D117).
    @Test func compressedSessionsAreIgnored() {
        let h = CodexHome()
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: Self.limits())], day: now, name: "rollout-x.jsonl.zst", modified: now)
        #expect(read(h).status == .noSessions)
    }

    /// Only the last 256 KB is read: an event further back than that isn't seen.
    @Test func onlyTheTailIsRead() {
        let h = CodexHome()
        let filler = Array(repeating: Self.chatter[1], count: (CodexReader.tailBytes / Self.chatter[1].utf8.count) + 50)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: Self.limits())] + filler, day: now, modified: now)
        #expect(read(h).status == .waitingForReply)
    }

    // MARK: Plans without limits, format changes

    @Test(arguments: ["null", "{}", #"{"primary":null,"secondary":null}"#])
    func noPlanLimits(rateLimits: String) {
        let h = CodexHome()
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: rateLimits)], day: now, modified: now)
        let r = read(h)
        #expect(r.status == .noPlanLimits)
        #expect(r.usage == nil)   // never "0%"
    }

    @Test func missingRateLimitsKeyMeansNoPlanLimits() {
        let h = CodexHome()
        let line = #"{"timestamp":"\#(Self.iso(now.addingTimeInterval(-60)))","type":"event_msg","payload":{"type":"token_count","info":null}}"#
        h.rollout([line], day: now, modified: now)
        #expect(read(h).status == .noPlanLimits)
    }

    @Test func unknownShapeMeansFormatChanged() {
        let h = CodexHome()
        let l = #"{"primary":{"pct":12,"minutes":300},"secondary":{"pct":40,"minutes":10080}}"#
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: l)], day: now, modified: now)
        let r = read(h)
        #expect(r.status == .formatChanged)
        #expect(r.usage == nil)
    }

    // MARK: Safety: read-only, no symlinks

    @Test func filesAreOnlyRead() throws {
        let h = CodexHome()
        let url = h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: Self.limits())], day: now, modified: now)
        chmod(url.path, 0o400)   // read-only for its owner: reading must still work
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = try Data(contentsOf: url)
        #expect(read(h).status == .ok)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
        #expect(before[.size] as? Int == after[.size] as? Int)
        #expect(try Data(contentsOf: url) == bytes)
        #expect((after[.posixPermissions] as? Int) == 0o400)
    }

    @Test func symlinkedRolloutIsNotFollowed() throws {
        let h = CodexHome()
        let elsewhere = makeTempHome().appendingPathComponent("elsewhere.jsonl")
        try Data((Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: Self.limits()) + "\n").utf8).write(to: elsewhere)
        let url = h.rollout(Self.chatter, day: now, name: "rollout-real.jsonl", modified: now.addingTimeInterval(-600))
        try FileManager.default.createSymbolicLink(at: url.deletingLastPathComponent().appendingPathComponent("rollout-link.jsonl"), withDestinationURL: elsewhere)
        #expect(read(h).status == .waitingForReply)
    }

    // MARK: Privacy (PRD section 2, lesson 17)

    /// Invented secrets on other lines, and in fields of the usage event that Wiggleroom must
    /// ignore. None may reach the reading, its memory dump, the saved file, the App Group file or
    /// any text the widget shows.
    @Test func nothingButNumbersLeavesTheSessionFile() throws {
        let fakePath = "/" + "Users" + "/invented-person/secret-project/main.swift"
        let fakeKey = "sk-" + String(repeating: "q", count: 40)
        let secrets = ["TOP-SECRET-PROMPT", fakeKey, fakePath, "SECRET-BALANCE", "SECRET-LIMIT-NAME", "SECRET-MODEL"]
        let h = CodexHome()
        let secretLines = [
            #"{"timestamp":"2027-01-14T22:31:00.000Z","type":"response_item","payload":{"type":"message","content":"TOP-SECRET-PROMPT \#(fakeKey) \#(fakePath)"}}"#,
            #"{"timestamp":"2027-01-14T22:32:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"token_count TOP-SECRET-PROMPT"}}"#,
        ]
        let leaky = #"{"primary":{"used_percent":12,"window_minutes":300,"resets_at":1800026400,"note":"TOP-SECRET-PROMPT"},"secondary":{"used_percent":41,"window_minutes":10080,"resets_at":1800403200},"credits":{"balance":"SECRET-BALANCE"},"limit_name":"SECRET-LIMIT-NAME","plan_type":"\#(fakePath)"}"#
        let event = #"{"timestamp":"\#(Self.iso(now.addingTimeInterval(-60)))","type":"event_msg","payload":{"type":"token_count","info":{"model":"SECRET-MODEL","note":"\#(fakeKey)"},"rate_limits":\#(leaky)}}"#
        h.rollout(secretLines + [event] + secretLines, day: now, modified: now)

        let r = read(h)
        #expect(r.status == .ok)
        let usage = try #require(r.usage)

        var dumped = ""
        dump(r, to: &dumped)
        let places: [(String, String)] = [
            ("memory dump of the reading", dumped),
            ("description of the reading", String(describing: r)),
            ("encoded snapshot", String(decoding: try usage.encoded(), as: UTF8.self)),
        ]
        // The saved copy in Wiggleroom's folder, and the App Group file the widget reads.
        let paths = WiggleroomPaths(home: makeTempHome())
        try CodexStore.save(usage, paths: paths)
        let saved = String(decoding: try Data(contentsOf: paths.codexFile), as: UTF8.self)
        let group = makeTempHome()
        AppGroupFiles.publishTools([ToolSnapshot(tool: .codex, usage: usage)], to: group, now: now)
        let groupText = String(decoding: try Data(contentsOf: group.appendingPathComponent(AppGroupFiles.toolsName)), as: UTF8.self)
        // Everything the widget and popover would draw.
        let d = UsageFormatter.display(usage, context: DisplayContext(now: now, timeZone: TimeZone(identifier: vegas)!, clock: .twelveHour))
        let shown = ([d.asOfText] + d.rows.flatMap { [$0.title, $0.percentText, $0.resetText, $0.resetTextShort] }).joined(separator: "\n")

        for (place, text) in places + [("saved file", saved), ("App Group file", groupText), ("widget text", shown)] {
            for s in secrets {
                // JSON files write "/" as "\/", so look for that spelling too.
                let leaked = text.contains(s) || text.contains(s.replacingOccurrences(of: "/", with: "\\/"))
                #expect(!leaked, "\(place) contains invented secret \(s.prefix(6))…")
            }
        }
        #expect(Set(usage.limits.map(\.id)) == ["five_hour", "seven_day"])
    }

    // MARK: Speed and memory (lesson 15)

    /// A 500 MB session file: only its tail is read, in under 50 ms and 20 MB of memory.
    @Test func hugeFileIsFastAndSmall() throws {
        let h = CodexHome()
        let url = h.rollout(Self.chatter, day: now, modified: now)
        // Grow it to 500 MB without writing 500 MB (a sparse file), then add an event at the end.
        let fd = open(url.path, O_WRONLY)
        #expect(ftruncate(fd, 500 * 1024 * 1024) == 0)
        lseek(fd, 0, SEEK_END)
        let tail = Data(("\n" + Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: Self.limits()) + "\n").utf8)
        _ = tail.withUnsafeBytes { write(fd, $0.baseAddress, tail.count) }
        close(fd)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)

        _ = read(h)   // warm up file system caches
        let before = footprint()
        let start = Date()
        let r = read(h)
        let elapsed = Date().timeIntervalSince(start)
        let grew = footprint() - before
        #expect(r.status == .ok)
        #expect(elapsed < 0.05, "took \(Int(elapsed * 1000)) ms")
        #expect(grew < 20 * 1024 * 1024, "memory grew \(grew / 1024) KB")
    }

    func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    // MARK: Shown in three time zones, both clocks (lesson 11)

    @Test(arguments: [
        (vegas, ClockStyle.twelveHour, "Resets Monday 1:00 AM"), (vegas, .twentyFourHour, "Resets Monday 01:00"),
        (utc, .twelveHour, "Resets Monday 9:00 AM"), (utc, .twentyFourHour, "Resets Monday 09:00"),
        (tokyo, .twelveHour, "Resets Monday 6:00 PM"), (tokyo, .twentyFourHour, "Resets Monday 18:00"),
    ])
    func codexResetsShownLocally(tz: String, clock: ClockStyle, text: String) throws {
        let reset = date(2027, 1, 18, 9, tz: utc)
        let h = CodexHome()
        let l = Self.limits(secondary: #"{"used_percent":41,"window_minutes":10080,"resets_at":\#(Int(reset.timeIntervalSince1970))}"#)
        h.rollout([Self.tokenCount(at: now.addingTimeInterval(-60), rateLimits: l)], day: now, modified: now)
        let u = try #require(read(h).usage)
        let row = try #require(UsageFormatter.display(u, context: DisplayContext(now: now, timeZone: TimeZone(identifier: tz)!, clock: clock)).row("seven_day"))
        #expect(row.resetText == text)
        #expect(row.title == "This week")
    }
}
