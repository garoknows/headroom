import Foundation

/// The AI coding tools Wiggleroom can show. A tool is added only when it hands over its plan's
/// limits through a channel its maker supports (docs/TOOLS.md).
public enum Tool: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex

    /// The plain-text name shown everywhere (no logos or brand colors).
    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// One tool's numbers. `usage` is the same snapshot shape 0.1 used, so every rule (merging,
/// plausibility, rounding up, the 100% guard, "as of" staleness) works the same for every tool.
public struct ToolSnapshot: Codable, Equatable, Sendable {
    public var tool: Tool
    public var usage: UsageSnapshot

    public init(tool: Tool, usage: UsageSnapshot) {
        self.tool = tool
        self.usage = usage
    }
}

/// The App Group file from 0.2 on: one snapshot per connected tool. It has its own name
/// (`snapshots.json`), so 0.1 never reads it, and 0.2 keeps writing 0.1's `snapshot.json` for
/// Claude Code, so a downgrade keeps working.
public struct ToolsFile: Equatable, Sendable {
    public static let currentFormat = 2

    public var format: Int
    public var tools: [ToolSnapshot]

    public init(format: Int = ToolsFile.currentFormat, tools: [ToolSnapshot]) {
        self.format = format
        self.tools = tools
    }

    public func usage(_ tool: Tool) -> UsageSnapshot? { tools.first { $0.tool == tool }?.usage }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(Wire(format: format, tools: tools.map { WireTool(tool: $0.tool.rawValue, usage: $0.usage) }))
    }

    /// Reads the file. A tool this version doesn't know (written by a newer Wiggleroom) is
    /// skipped instead of making the whole file unreadable. Only the newest entry per tool counts.
    public static func decode(_ data: Data) -> ToolsFile? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard let w = try? d.decode(Wire.self, from: data), w.format == currentFormat else { return nil }
        var seen = Set<Tool>()
        var tools: [ToolSnapshot] = []
        for t in w.tools {
            guard let tool = Tool(rawValue: t.tool), let usage = t.usage, seen.insert(tool).inserted else { continue }
            tools.append(ToolSnapshot(tool: tool, usage: usage))
        }
        return ToolsFile(format: w.format, tools: tools)
    }

    private struct Wire: Codable {
        var format: Int
        var tools: [WireTool]
    }

    private struct WireTool: Codable {
        var tool: String
        var usage: UsageSnapshot?

        init(tool: String, usage: UsageSnapshot) {
            self.tool = tool
            self.usage = usage
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tool = try c.decode(String.self, forKey: .tool)
            usage = try? c.decode(UsageSnapshot.self, forKey: .usage)
        }
    }
}

/// Limits named by their length in minutes, for tools that report a window length instead of a
/// name (Codex). Never assumes "primary" means 5-hour (PRD section 4).
public enum WindowNaming {
    /// A stable limit id: about 300 minutes is the 5-hour window, about 10080 the weekly one,
    /// anything else `window_<minutes>`.
    public static func id(windowMinutes m: Int) -> String {
        if abs(m - 300) <= 30 { return LimitKind.session }
        if abs(m - 10080) <= 720 { return LimitKind.weekly }
        return "window_\(max(0, m))"
    }

    /// The row title: "5-hour", "This week", or "N-hour" / "N-day" for anything else.
    public static func label(windowMinutes m: Int) -> String {
        if abs(m - 300) <= 30 { return "5-hour" }
        if abs(m - 10080) <= 720 { return "This week" }
        if m >= 1440 { return "\(max(1, Int((Double(m) / 1440).rounded())))-day" }
        return "\(max(1, Int((Double(m) / 60).rounded())))-hour"
    }
}

/// One tool's card, ready to draw.
public struct ToolDisplay: Equatable, Sendable, Identifiable {
    public var tool: Tool
    public var display: UsageDisplay
    public var id: Tool { tool }

    public init(tool: Tool, display: UsageDisplay) {
        self.tool = tool
        self.display = display
    }

    /// How close this tool is to any of its limits: its highest percent among limits that have
    /// numbers (a limit whose reset passed doesn't count). -1 when it has none.
    public var closeness: Double {
        display.rows.filter { $0.percent != nil }.map(\.usedPercent).max() ?? -1
    }

    /// Its weekly percent (or its first limit's), for "Highest of my tools". -1 when unknown.
    public var weeklyPercent: Double {
        guard let p = display.primary, p.percent != nil else { return -1 }
        return p.usedPercent
    }

    /// Closest to a limit first; ties keep the usual order (Claude Code, then Codex).
    public static func closestFirst(_ tools: [ToolDisplay]) -> [ToolDisplay] {
        tools.enumerated().sorted { a, b in
            a.element.closeness != b.element.closeness ? a.element.closeness > b.element.closeness
                : (Tool.allCases.firstIndex(of: a.element.tool)! < Tool.allCases.firstIndex(of: b.element.tool)!)
        }.map(\.element)
    }
}

/// What the menu bar item shows.
public enum MenuBarChoice: String, CaseIterable, Codable, Sendable {
    /// The weekly percent of whichever connected tool is closest to its limit (the default).
    case highest
    case claudeCode = "claude-code"
    case codex

    public static let `default` = MenuBarChoice.highest

    public var title: String {
        switch self {
        case .highest: "Highest of my tools"
        case .claudeCode: Tool.claudeCode.displayName
        case .codex: Tool.codex.displayName
        }
    }

    /// The tool whose weekly row the menu bar shows, or nil when that tool has no numbers.
    public func pick(from tools: [ToolDisplay]) -> ToolDisplay? {
        switch self {
        case .claudeCode: return tools.first { $0.tool == .claudeCode }
        case .codex: return tools.first { $0.tool == .codex }
        case .highest:
            // The first tool of the "Highest of my tools" order, which the popover uses too.
            return ToolDisplay.highestFirst(tools).first
        }
    }
}

/// The menu bar item's text and tooltip.
public enum MenuBarText {
    /// Just the percent: the tooltip names the tool, and the popover's top row is the same tool
    /// (0.2.1). 0.2.0 and 0.2.1 added a C or X tag, removed in 0.2.2 because a lone letter confused people.
    public static func make(choice: MenuBarChoice, picked: ToolDisplay?) -> (title: String, tooltip: String) {
        guard let picked, let row = picked.display.primary, let pct = row.percent else {
            let which = choice == .highest ? "" : " from \(choice.title)"
            return ("", "Wiggleroom: no numbers\(which) yet")
        }
        return (" \(pct)%", "Wiggleroom: \(picked.tool.displayName), \(row.title) \(row.percentText)")
    }
}

// MARK: 0.2.1: one order for the menu bar and the popover, the compact popover, the footer

extension ToolDisplay {
    /// The "Highest of my tools" order: highest weekly percent (or first limit) first, a tool
    /// without numbers last, and ties in the usual order (Claude Code, then Codex).
    public static func highestFirst(_ tools: [ToolDisplay]) -> [ToolDisplay] {
        let rank = { (t: ToolDisplay) in Tool.allCases.firstIndex(of: t.tool) ?? 0 }
        return tools.sorted { a, b in
            a.weeklyPercent != b.weeklyPercent ? a.weeklyPercent > b.weeklyPercent : rank(a) < rank(b)
        }
    }

    /// The rows this tool gets in the compact (two-tool) popover: its weekly row (or its first
    /// limit), then any other limit at 75% or more, the same point where its bar turns amber.
    /// A limit whose reset has passed shows no percent, so it is never added.
    public var compactRows: [LimitRow] {
        guard let primary = display.primary else { return [] }
        return [primary] + display.rows.filter { $0.id != primary.id && $0.percent != nil && $0.level != .normal }
    }
}

extension MenuBarChoice {
    /// The popover's order: the tool the menu bar shows comes first, so the two never disagree.
    /// The rest follow the "Highest of my tools" order.
    public func popoverOrder(_ tools: [ToolDisplay]) -> [ToolDisplay] {
        let ordered = ToolDisplay.highestFirst(tools)
        guard let top = pick(from: tools) else { return ordered }
        return [top] + ordered.filter { $0.tool != top.tool }
    }
}

/// What a tool's watcher is doing, for the popover's footer.
public enum WatchStatus: Equatable, Sendable {
    case starting
    case watching
    /// Not watching, with the reason in plain words.
    case problem(String)
}

/// One line of the popover's footer.
public struct WatcherLine: Equatable, Sendable {
    public var text: String
    /// False when the line reports a problem (it gets the warning icon).
    public var ok: Bool

    public init(text: String, ok: Bool) {
        self.text = text
        self.ok = ok
    }
}

/// The popover's footer: one line naming every connected tool that is being watched, and a line
/// of its own for each one that isn't (problems first, so they're seen).
public enum WatcherSummary {
    /// Codex's folder is missing (Codex isn't installed yet) or macOS wouldn't watch it.
    public static let codexNotFound = "its folder isn't there or can't be watched"
    /// Codex is connected but its watcher was stopped.
    public static let codexStopped = "open Settings and click Check Again"

    /// `tools` are the connected tools. With none, Claude Code's watcher is the one setup waits on.
    public static func lines(tools: [Tool], claudeCode: WatchStatus, codex: WatchStatus) -> [WatcherLine] {
        let shown = tools.isEmpty ? [Tool.claudeCode] : Tool.allCases.filter(tools.contains)
        var out: [WatcherLine] = []
        var watching: [String] = []
        for tool in shown {
            switch tool == .claudeCode ? claudeCode : codex {
            case .watching: watching.append(tool.displayName)
            case .starting: out.append(WatcherLine(text: "Starting to watch \(tool.displayName)…", ok: false))
            case .problem(let why): out.append(WatcherLine(text: "Not watching \(tool.displayName): \(why)", ok: false))
            }
        }
        if watching.count == 1 {
            // One tool: the same words as 0.2.0.
            out.append(WatcherLine(text: "Watching for new numbers from \(watching[0])", ok: true))
        } else if watching.count > 1 {
            // Short enough for one line in the popover.
            let names = watching.dropLast().joined(separator: ", ") + " and " + watching.last!
            out.append(WatcherLine(text: "Watching \(names)", ok: true))
        }
        return out
    }
}

// MARK: 0.2.2: the popover's "As of" lines

/// Which "As of" lines the compact popover shows.
public struct AsOfPlan: Equatable, Sendable {
    /// The shared line's numbers (time and freshness), or nil when there are no tools.
    public var shared: UsageDisplay?
    /// Tools that get a line of their own under their rows.
    public var separate: Set<Tool>

    public init(shared: UsageDisplay?, separate: Set<Tool>) {
        self.shared = shared
        self.separate = separate
    }
}

extension ToolDisplay {
    /// The compact popover's "As of" lines (DECISIONS D180). The shared line covers the tools
    /// as fresh as the freshest one, and shows the oldest time among them, so it is never fresher
    /// than any number it covers. A tool at a worse level (amber after 30 minutes, dimmed after
    /// 6 hours) gets its own line, so a tool nobody has used lately can't turn the shared line amber.
    public static func asOfPlan(_ tools: [ToolDisplay]) -> AsOfPlan {
        func level(_ f: Freshness) -> Int {
            switch f {
            case .fresh: 0
            case .stale: 1
            case .veryStale: 2
            }
        }
        guard let best = tools.map({ level($0.display.freshness) }).min() else { return AsOfPlan(shared: nil, separate: []) }
        let covered = tools.filter { level($0.display.freshness) == best }
        let separate = Set(tools.filter { level($0.display.freshness) > best }.map(\.tool))
        return AsOfPlan(shared: covered.min { $0.display.updatedAt < $1.display.updatedAt }?.display, separate: separate)
    }
}

// MARK: 0.2.3: the medium widget's All tools "As of" line

/// The medium widget's one bottom line with the popover's rule (D180, D186, D187):
/// "As of 9:29 PM · Codex 8:21 PM", the older tool's part in amber.
public struct WidgetAsOfLine: Equatable, Sendable {
    /// One older tool's part.
    public struct Older: Equatable, Sendable {
        public var tool: Tool
        public var time: String
        public var day: String?
    }

    /// The shared "As of" (time and freshness), or nil when there are no tools.
    public var shared: UsageDisplay?
    public var older: [Older]

    /// How many shorter versions there are (0 is the full line).
    public static let levels = 3

    /// The same split as the popover (`ToolDisplay.asOfPlan`): the shared time covers the tools
    /// as fresh as the freshest one (the oldest of their times); each tool at a worse level adds
    /// its own name and time, in the tools' order.
    public static func make(_ tools: [ToolDisplay]) -> WidgetAsOfLine {
        let plan = ToolDisplay.asOfPlan(tools)
        let older = tools.filter { plan.separate.contains($0.tool) }
            .map { Older(tool: $0.tool, time: $0.display.asOfTime, day: $0.display.asOfDay) }
        return WidgetAsOfLine(shared: plan.shared, older: older)
    }

    /// Each older tool's part, from longest (level 0) to shortest: "Codex Mon 9:01 PM", then
    /// "Codex Mon" (a time today stays, since it is all there is to say), then just "Codex".
    /// The widget picks the longest that fits, so the line is never cut off.
    public func olderTexts(level: Int) -> [String] {
        older.map { o in
            let name = o.tool.displayName
            switch level {
            case ..<1: return "\(name) \(o.time)"
            case 1: return "\(name) \(o.day ?? o.time)"
            default: return name
            }
        }
    }
}
