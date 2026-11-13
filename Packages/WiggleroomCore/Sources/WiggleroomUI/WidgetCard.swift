import WiggleroomCore
import SwiftUI

/// Which tool a widget shows (the widget's "Tool" setting).
public enum WidgetTool: String, CaseIterable, Sendable {
    case claudeCode, codex, all

    public var tool: Tool? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .all: nil
        }
    }
}

/// What a widget shows, worked out from the App Group file and the widget's Tool setting.
public enum WidgetContent: Equatable, Sendable {
    /// One tool's numbers, with its name on top.
    case tool(ToolDisplay)
    /// Every tool that has numbers (All tools), closest to a limit first.
    case all([ToolDisplay])
    /// No numbers yet for this tool (or for any tool, when nil).
    case waiting(Tool?)
    /// This build can't share numbers with widgets (unsigned).
    case unavailable

    /// Picks the content for a widget. 0.1 widgets get Claude Code (the Tool setting's default).
    public static func make(choice: WidgetTool, tools: [ToolSnapshot], groupAvailable: Bool, context: DisplayContext) -> WidgetContent {
        guard groupAvailable else { return .unavailable }
        let displays = tools.map { ToolDisplay(tool: $0.tool, display: UsageFormatter.display($0.usage, context: context)) }
        if let one = choice.tool {
            return displays.first { $0.tool == one }.map { .tool($0) } ?? .waiting(one)
        }
        let ordered = ToolDisplay.closestFirst(displays)
        if ordered.isEmpty { return .waiting(nil) }
        return ordered.count == 1 ? .tool(ordered[0]) : .all(ordered)
    }
}

/// The widget, drawn the same way in Notification Center, the renders and the tests.
public struct WidgetCard: View {
    let content: WidgetContent
    let layout: CardLayout
    let live: Bool
    @Environment(\.colorScheme) private var scheme

    public init(content: WidgetContent, layout: CardLayout, live: Bool = true) {
        self.content = content
        self.layout = layout
        self.live = live
    }

    public var body: some View {
        let p = Palette(scheme)
        Group {
            switch content {
            case .tool(let t):
                if layout == .small {
                    SmallUsage(display: t.display, palette: p, live: live, toolName: t.tool.displayName)
                } else {
                    // The rows keep 0.1's layout; the tool's name goes on the "as of" line.
                    RowsUsage(display: t.display, palette: p, live: live, maxRows: 2, fillHeight: true, toolName: t.tool.displayName)
                }
            case .all(let tools):
                if layout == .small, let top = MenuBarChoice.highest.pick(from: tools) {
                    SmallUsage(display: top.display, palette: p, live: live, toolName: top.tool.displayName)
                } else {
                    AllToolsRows(tools: tools, palette: p)
                }
            case .waiting(let tool):
                if tool == .codex {
                    WaitingCard(layout: layout, palette: p, title: "Codex",
                                text: layout == .small ? "Connect Codex in Wiggleroom's Settings." : "Open Wiggleroom, go to Settings, Tools, and click Connect next to Codex. Your numbers appear after Codex's next reply.")
                } else {
                    EmptyCard(layout: layout, palette: p)
                }
            case .unavailable:
                UnavailableCard(layout: layout, palette: p)
            }
        }
        .foregroundStyle(p.text)
    }
}

struct ToolHeading: View {
    let name: String
    let palette: Palette
    var body: some View {
        Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.secondary).lineLimit(1)
    }
}

/// All tools, medium: one weekly row per tool, with the tool's name as the row's title.
/// The two-tool popover (0.2.1) uses the same rows, plus any other limit at 75% or more.
struct AllToolsRows: View {
    let tools: [ToolDisplay]
    let palette: Palette
    /// The popover's 5-hour countdown ticks; the widget's rows show clock times.
    var live = false
    /// The popover also shows each tool's other limits at 75% or more (`compactRows`); the
    /// medium widget only has room for the weekly rows.
    var popover = false

    var body: some View {
        if popover { popoverBody } else { widgetBody }
    }

    /// The widget: the rows, then one "As of" line (`AllToolsAsOfLine`).
    private var widgetBody: some View {
        let entries = tools.prefix(3).flatMap { t in (t.display.primary.map { [$0] } ?? []).map { Entry(tool: t, row: $0) } }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(entries) { e in
                LimitRowView(row: Self.titled(e.row, e.tool), palette: palette, live: live,
                             dimmed: e.tool.display.freshness == .veryStale, window: e.row.title)
            }
            Spacer(minLength: 0)
            AllToolsAsOfLine(tools: Array(tools.prefix(3)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The popover (0.2.2): a tool whose numbers are older than the freshest tool's level gets its
    /// own "Codex · As of 8:21 PM" line under its rows; the shared line covers the rest (D180).
    private var popoverBody: some View {
        let plan = ToolDisplay.asOfPlan(tools)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(tools) { t in
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(t.compactRows) { row in
                            LimitRowView(row: Self.titled(row, t), palette: palette, live: live,
                                         dimmed: t.display.freshness == .veryStale, window: row.title)
                        }
                    }
                    if plan.separate.contains(t.tool) {
                        AsOfLine(display: t.display, palette: palette, toolName: t.tool.displayName)
                    }
                }
            }
            if let shared = plan.shared { AsOfLine(display: shared, palette: palette) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One row: unique across tools (both have a "seven_day" limit).
    struct Entry: Identifiable {
        let tool: ToolDisplay
        let row: LimitRow
        var id: String { "\(tool.tool.rawValue)/\(row.id)" }
    }

    /// "Codex" as the title, "This week · Resets Monday 1:00 AM" below it.
    static func titled(_ original: LimitRow, _ t: ToolDisplay) -> LimitRow {
        var row = original
        let window = row.title
        row.title = t.tool.displayName
        row.resetText = "\(window) · \(row.resetTextShort.replacingOccurrences(of: "Resets ", with: "resets "))"
        return row
    }
}

struct WaitingCard: View {
    let layout: CardLayout
    let palette: Palette
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WiggleroomMark().frame(width: 22, height: 22)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            Text(text).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The popover's cards, in the order given (the menu bar's tool first). One tool with numbers
/// gets its full card under its name. Two or more get the compact rows (0.2.1): each tool's weekly
/// row, plus any other limit at 75% or more, and one "As of" line. A connected tool without
/// numbers yet says when they'll come.
public struct ToolBlocks: View {
    let tools: [ToolDisplay]
    let waiting: [Tool]
    let live: Bool
    @Environment(\.colorScheme) private var scheme

    public init(tools: [ToolDisplay], waiting: [Tool], live: Bool = true) {
        self.tools = tools
        self.waiting = waiting
        self.live = live
    }

    public var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 12) {
            if tools.count >= 2 {
                AllToolsRows(tools: tools, palette: p, live: live, popover: true)
            } else {
                ForEach(tools) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        ToolHeading(name: t.tool.displayName, palette: p)
                        UsageCard(content: .usage(t.display), layout: .popover, live: live)
                    }
                }
            }
            ForEach(Array(waiting.enumerated()), id: \.element) { i, tool in
                if i > 0 || !tools.isEmpty { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                    ToolHeading(name: tool.displayName, palette: p)
                    Text(tool == .codex ? "Your numbers appear after Codex's next reply." : "Your numbers appear after Claude Code's next reply.")
                        .font(.system(size: 11)).foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(p.text)
    }
}

/// The medium widget's All tools "As of" line (0.2.3, D186 and D187): "As of 9:29 PM · Codex 8:21 PM",
/// the older tool's part in amber with the clock icon. It uses the longest version that fits, so
/// it is never cut off.
public struct AllToolsAsOfLine: View {
    let tools: [ToolDisplay]
    let level: Int?
    @Environment(\.colorScheme) private var scheme

    /// `level` nil picks the longest version that fits; a number draws that version (tests, renders).
    public init(tools: [ToolDisplay], level: Int? = nil) {
        self.tools = tools
        self.level = level
    }

    public var body: some View {
        let line = WidgetAsOfLine.make(tools)
        let p = Palette(scheme)
        if let level {
            version(line, level: level, palette: p)
        } else {
            ViewThatFits(in: .horizontal) {
                version(line, level: 0, palette: p)
                version(line, level: 1, palette: p)
                version(line, level: 2, palette: p)
            }
        }
    }

    private func version(_ line: WidgetAsOfLine, level: Int, palette p: Palette) -> some View {
        HStack(spacing: 4) {
            if let shared = line.shared { AsOfLine(display: shared, palette: p) }
            ForEach(Array(line.olderTexts(level: level).enumerated()), id: \.offset) { _, text in
                Text("·").foregroundStyle(p.secondary)
                HStack(spacing: 3) {
                    Image(systemName: "clock.badge.exclamationmark").imageScale(.small)
                    Text(text)
                }
                .foregroundStyle(p.amber)
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((line.shared.map { $0.freshness == .fresh ? [$0.asOfText] : ["\($0.asOfText). These numbers may be out of date"] } ?? [])
            .appending(contentsOf: line.older.map { "\($0.tool.displayName) as of \($0.time). These numbers may be out of date" })
            .joined(separator: ". "))
    }
}

private extension Array {
    func appending(contentsOf other: [Element]) -> [Element] { self + other }
}
