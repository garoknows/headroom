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

    /// One letter for the menu bar when it shows "Highest of my tools".
    public var tag: String {
        switch self {
        case .claudeCode: "C"
        case .codex: "X"
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
