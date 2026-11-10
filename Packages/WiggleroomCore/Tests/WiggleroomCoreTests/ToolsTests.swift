import Foundation
import Testing
@testable import WiggleroomCore

/// 0.2's per-tool data model, and moving from 0.1 to 0.2 (and back) without losing anything.
@Suite struct ToolsTests {
    /// The fixtures' moment: a minute after their `updatedAt`.
    let now = Date(timeIntervalSince1970: 1_800_040_060)

    func codexUsage(_ week: Double, at t: Date) -> UsageSnapshot {
        UsageSnapshot(updatedAt: t, limits: [
            LimitWindow(id: "five_hour", usedPercent: 12, resetsAt: t.addingTimeInterval(3600), label: "5-hour", windowMinutes: 300),
            LimitWindow(id: "seven_day", usedPercent: week, resetsAt: t.addingTimeInterval(4 * 86400), label: "This week", windowMinutes: 10080),
        ])
    }

    func groupFolder() -> URL {
        let g = makeTempHome().appendingPathComponent("group", isDirectory: true)
        try! FileManager.default.createDirectory(at: g, withIntermediateDirectories: true)
        return g
    }

    // MARK: Migration (lesson 17: seen failing against stubs first)

    /// A widget placed with 0.1 keeps showing Claude Code after the upgrade, before the 0.2 app
    /// has written its new file.
    @Test func oneDotOneAppGroupFileIsReadAsClaudeCode() throws {
        let g = groupFolder()
        try Fixture.data("app-group-0.1-snapshot.json").write(to: g.appendingPathComponent(AppGroupFiles.snapshotName))
        let tools = AppGroupFiles.readTools(in: g, now: now)
        #expect(tools.map(\.tool) == [.claudeCode])
        #expect(tools.first?.usage.limit("seven_day")?.usedPercent == 41.5)
        #expect(tools.first?.usage.limit("five_hour")?.usedPercent == 23)
    }

    /// After the upgrade the app writes both files; 0.1's file keeps exactly Claude Code's
    /// numbers in 0.1's format, so going back to 0.1 shows the same widget.
    @Test func publishingKeepsTheOneDotOneFileForDowngrade() throws {
        let g = groupFolder()
        let claude = try #require(UsageSnapshot.decode(Fixture.data("app-group-0.1-snapshot.json")))
        let codex = codexUsage(55, at: now.addingTimeInterval(-30))
        #expect(AppGroupFiles.publishTools([ToolSnapshot(tool: .claudeCode, usage: claude), ToolSnapshot(tool: .codex, usage: codex)], to: g, now: now))
        // 0.1's reader sees Claude Code only, unchanged.
        let old = try #require(FileManager.default.contents(atPath: g.appendingPathComponent(AppGroupFiles.snapshotName).path))
        #expect(UsageSnapshot.decode(old) == claude)
        // 0.1's reader can't misread the new file (different name and format).
        let new = try #require(FileManager.default.contents(atPath: g.appendingPathComponent(AppGroupFiles.toolsName).path))
        #expect(UsageSnapshot.decode(new) == nil)
        // 0.2 reads both tools from the new file.
        let tools = AppGroupFiles.readTools(in: g, now: now)
        #expect(Set(tools.map(\.tool)) == [.claudeCode, .codex])
        #expect(tools.first { $0.tool == .codex }?.usage == codex)
    }

    /// A disconnected tool disappears from the widget's file; good numbers are never replaced by
    /// bad or older ones (lesson 12), tool by tool.
    @Test func publishingRemovesDisconnectedToolsAndNeverWorsensOne() throws {
        let g = groupFolder()
        let claude = try #require(UsageSnapshot.decode(Fixture.data("app-group-0.1-snapshot.json")))
        let codex = codexUsage(55, at: now.addingTimeInterval(-30))
        AppGroupFiles.publishTools([ToolSnapshot(tool: .claudeCode, usage: claude), ToolSnapshot(tool: .codex, usage: codex)], to: g, now: now)
        // Same data again: nothing to write, no widget reload.
        #expect(!AppGroupFiles.publishTools([ToolSnapshot(tool: .claudeCode, usage: claude), ToolSnapshot(tool: .codex, usage: codex)], to: g, now: now))
        // Older Codex numbers don't replace newer ones.
        let older = codexUsage(10, at: now.addingTimeInterval(-3600))
        AppGroupFiles.publishTools([ToolSnapshot(tool: .claudeCode, usage: claude), ToolSnapshot(tool: .codex, usage: older)], to: g, now: now)
        #expect(AppGroupFiles.readTools(in: g, now: now).first { $0.tool == .codex }?.usage == codex)
        // Implausible Codex numbers don't either.
        var bad = codexUsage(55, at: now); bad.limits[0].usedPercent = 400
        AppGroupFiles.publishTools([ToolSnapshot(tool: .claudeCode, usage: claude), ToolSnapshot(tool: .codex, usage: bad)], to: g, now: now)
        #expect(AppGroupFiles.readTools(in: g, now: now).first { $0.tool == .codex }?.usage == codex)
        // Codex disconnected: gone from the widget's file; Claude Code stays.
        #expect(AppGroupFiles.publishTools([ToolSnapshot(tool: .claudeCode, usage: claude)], to: g, now: now))
        #expect(AppGroupFiles.readTools(in: g, now: now).map(\.tool) == [.claudeCode])
    }

    /// 0.1's alert record ("90" fired this week) becomes Claude Code's weekly key, so the same
    /// alert isn't sent again right after the upgrade.
    @Test func oneDotOneAlertRecordMigrates() throws {
        let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate
        let old = try d.decode(AlertRecord.self, from: Fixture.data("alert-record-0.1.json"))
        let m = old.migrated()
        #expect(m.fired[AlertRecord.key(.claudeCode, LimitKind.weekly, 90)] == old.fired["90"])
        #expect(m.fired["90"] == nil)
        #expect(m.migrated() == m)   // migrating twice changes nothing
    }

    // MARK: The file format

    @Test func toolsFileSkipsUnknownToolsAndDuplicates() throws {
        let json = #"{"format":2,"tools":[{"tool":"some-future-tool","usage":{"format":1,"updatedAt":1800040000,"limits":[]}},{"tool":"codex","usage":{"format":1,"updatedAt":1800040000,"limits":[{"id":"seven_day","usedPercent":5,"outOfRange":false}]}},{"tool":"codex","usage":{"format":1,"updatedAt":1800040001,"limits":[]}}]}"#
        let f = try #require(ToolsFile.decode(Data(json.utf8)))
        #expect(f.tools.map(\.tool) == [.codex])
        #expect(f.usage(.codex)?.limit("seven_day")?.usedPercent == 5)
        #expect(ToolsFile.decode(Data(#"{"format":3,"tools":[]}"#.utf8)) == nil)
    }

    @Test func claudeCodeLimitsKeepTheirOneDotOneKeys() throws {
        // The status line program's file must not grow new keys (Claude Code limits have no label).
        let s = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 3, resetsAt: now)])
        let obj = try #require(try JSONSerialization.jsonObject(with: s.encoded()) as? [String: Any])
        let limit = try #require((obj["limits"] as? [[String: Any]])?.first)
        #expect(Set(limit.keys) == UsageSnapshot.allowedLimitKeys)
    }

    @Test(arguments: [
        (300, "five_hour", "5-hour"), (299, "five_hour", "5-hour"), (10080, "seven_day", "This week"),
        (10079, "seven_day", "This week"), (60, "window_60", "1-hour"), (1440, "window_1440", "1-day"),
        (4320, "window_4320", "3-day"), (720, "window_720", "12-hour"),
    ])
    func windowNamesComeFromTheirLength(minutes: Int, id: String, label: String) {
        #expect(WindowNaming.id(windowMinutes: minutes) == id)
        #expect(WindowNaming.label(windowMinutes: minutes) == label)
        #expect(LimitKind.isSupported(id))
    }

    @Test func labelsAreShownForToolsThatHaveThem() {
        let s = codexUsage(41, at: now)
        let d = UsageFormatter.display(s, context: DisplayContext(now: now, timeZone: TimeZone(identifier: "UTC")!, clock: .twelveHour))
        #expect(d.rows.map(\.title) == ["5-hour", "This week"])
    }
}
