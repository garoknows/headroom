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

    /// Every widget state at the size Notification Center gives it (content area inside the
    /// 16-point margin): it must need no more height than there is.
    @Test func everyWidgetStateFits() {
        let both = [claude, codex]
        let contents: [(String, WidgetContent)] = [
            ("claude", WidgetContent.make(choice: .claudeCode, tools: both, groupAvailable: true, context: ctx)),
            ("codex", WidgetContent.make(choice: .codex, tools: both, groupAvailable: true, context: ctx)),
            ("all", WidgetContent.make(choice: .all, tools: both, groupAvailable: true, context: ctx)),
            ("codex waiting", .waiting(.codex)), ("claude waiting", .waiting(.claudeCode)), ("unavailable", .unavailable),
        ]
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
