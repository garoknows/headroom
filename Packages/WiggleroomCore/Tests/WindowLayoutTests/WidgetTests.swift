import AppKit
import SwiftUI
import Testing
import WiggleroomCore
import WiggleroomUI
import WiggleroomWindows

/// The configurable widget: what each Tool setting shows, and that every state fits the
/// widget's real size (lesson 26).
@MainActor
@Suite struct WidgetTests {
    let ctx = PreviewStates.context
    var claude: ToolSnapshot { ToolSnapshot(tool: .claudeCode, usage: SampleData.snapshot(now: PreviewStates.now, timeZone: PreviewStates.timeZone, age: 4 * 60)) }
    var codex: ToolSnapshot { ToolSnapshot(tool: .codex, usage: PreviewStates.codexUsage) }

    /// A widget placed with 0.1 has no Tool setting yet; it gets the default, Claude Code, and
    /// reads 0.1's App Group file until the 0.2 app writes the new one.
    @Test func oneDotOneWidgetKeepsShowingClaudeCode() throws {
        let group = FileManager.default.temporaryDirectory.appendingPathComponent("wg-\(UUID().uuidString)", isDirectory: true)
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WIGGLEROOM_TEST_TMP"] ?? group.deletingLastPathComponent().path)
            .appendingPathComponent("wg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try claude.usage.encoded().write(to: folder.appendingPathComponent(AppGroupFiles.snapshotName))
        let tools = AppGroupFiles.readTools(in: folder, now: PreviewStates.now)
        let content = WidgetContent.make(choice: .claudeCode, tools: tools, groupAvailable: true, context: ctx)
        guard case .tool(let t) = content else { Issue.record("expected Claude Code's numbers, got \(content)"); return }
        #expect(t.tool == .claudeCode)
        #expect(t.display.primary?.percent == 41)
    }

    @Test func eachToolSettingShowsTheRightThing() {
        let both = [claude, codex]
        guard case .tool(let c) = WidgetContent.make(choice: .codex, tools: both, groupAvailable: true, context: ctx) else { Issue.record("codex"); return }
        #expect(c.tool == .codex)
        guard case .all(let all) = WidgetContent.make(choice: .all, tools: both, groupAvailable: true, context: ctx) else { Issue.record("all"); return }
        #expect(all.map(\.tool) == [.codex, .claudeCode])   // Codex is at 64%, closest to a limit
        #expect(WidgetContent.make(choice: .codex, tools: [claude], groupAvailable: true, context: ctx) == .waiting(.codex))
        #expect(WidgetContent.make(choice: .all, tools: [], groupAvailable: true, context: ctx) == .waiting(nil))
        #expect(WidgetContent.make(choice: .all, tools: both, groupAvailable: false, context: ctx) == .unavailable)
        // All tools with one tool connected is just that tool.
        guard case .tool(let only) = WidgetContent.make(choice: .all, tools: [claude], groupAvailable: true, context: ctx) else { Issue.record("one"); return }
        #expect(only.tool == .claudeCode)
    }

    /// 0.2.3: All tools with a tool whose numbers are older (D186, D187).
    var oldToolStates: [(String, WidgetContent)] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = PreviewStates.timeZone
        func all(now: Date, claudeMinutes: Double, codexMinutes: Double) -> WidgetContent {
            let ctx = DisplayContext(now: now, timeZone: PreviewStates.timeZone, clock: .twelveHour)
            let c = SampleData.snapshot(now: now, timeZone: PreviewStates.timeZone, age: claudeMinutes * 60)
            let x = UsageSnapshot(updatedAt: now.addingTimeInterval(-codexMinutes * 60), limits: [
                LimitWindow(id: LimitKind.session, usedPercent: 12, resetsAt: now.addingTimeInterval(2 * 3600), label: "5-hour", windowMinutes: 300),
                LimitWindow(id: LimitKind.weekly, usedPercent: 64, resetsAt: now.addingTimeInterval(4 * 86400), label: "This week", windowMinutes: 10080),
            ])
            return WidgetContent.make(choice: .all, tools: [ToolSnapshot(tool: .claudeCode, usage: c), ToolSnapshot(tool: .codex, usage: x)],
                                      groupAvailable: true, context: ctx)
        }
        let afterMidnight = cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 0, minute: 30))!
        return [
            ("all, Codex 70 minutes old", all(now: PreviewStates.now, claudeMinutes: 2, codexMinutes: 70)),
            ("all, Codex 3 days old", all(now: PreviewStates.now, claudeMinutes: 2, codexMinutes: 3 * 1440 + 30)),
            ("all, both stale", all(now: PreviewStates.now, claudeMinutes: 120, codexMinutes: 180)),
            // The longest texts: Claude Code from 11:58 PM yesterday (stale), Codex 8 days old.
            ("all, longest dates", all(now: afterMidnight, claudeMinutes: 32, codexMinutes: 8 * 1440 + 32)),
        ]
    }

    /// 0.2.3: the All tools "As of" line is never cut off. The full line fits the medium widget's
    /// 332 points even with the longest dates, and each shorter version really is shorter, down
    /// to one that fits a much narrower widget.
    @Test func allToolsAsOfLineIsNeverCutOff() {
        for (name, content) in oldToolStates {
            guard case .all(let tools) = content else { Issue.record("\(name) isn't All tools: \(content)"); continue }
            let widths = (0..<WidgetAsOfLine.levels).map {
                NSHostingView(rootView: AllToolsAsOfLine(tools: tools, level: $0)).fittingSize.width
            }
            #expect(widths[0] <= 332 + 0.5, "\(name): the full line needs \(widths[0]) of 332 points")
            #expect(widths == widths.sorted(by: >), "\(name): a shorter version is wider: \(widths)")
            if name == "all, longest dates" {
                #expect(widths[0] > widths[1] && widths[1] > widths[2], "longest dates: each version should be shorter: \(widths)")
                #expect(widths[2] <= 200, "the shortest version needs \(widths[2]) points")
            }
        }
    }

    /// Every widget state at the size Notification Center gives it (content area inside the
    /// 16-point margin): it must need no more height than there is.
    @Test func everyWidgetStateFits() {
        let both = [claude, codex]
        let contents: [(String, WidgetContent)] = [
            ("claude", WidgetContent.make(choice: .claudeCode, tools: both, groupAvailable: true, context: ctx)),
            ("codex", WidgetContent.make(choice: .codex, tools: both, groupAvailable: true, context: ctx)),
            ("all", WidgetContent.make(choice: .all, tools: both, groupAvailable: true, context: ctx)),
            ("codex waiting", .waiting(.codex)), ("claude waiting", .waiting(.claudeCode)), ("unavailable", .unavailable),
        ] + oldToolStates
        for (name, content) in contents {
            for (layout, size) in [(CardLayout.small, CGSize(width: 138, height: 138)), (.medium, CGSize(width: 332, height: 138))] {
                let need = NSHostingView(rootView: WidgetCard(content: content, layout: layout, live: false)
                    .frame(width: size.width).fixedSize(horizontal: false, vertical: true)).fittingSize
                #expect(need.height <= size.height + 0.5, "\(name) \(layout): needs \(need.height) of \(size.height) points")
                #expect(need.width <= size.width + 0.5, "\(name) \(layout): needs \(need.width) of \(size.width) points wide")
            }
        }
    }
}
