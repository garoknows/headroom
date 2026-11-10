import AppIntents
import WiggleroomCore
import WiggleroomUI
import SwiftUI
import WidgetKit

// The Wiggleroom widget. It reads the App Group files that the Wiggleroom app writes, and
// nothing else: no network, no Keychain, no other files (lesson 10).

@main
struct WiggleroomWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

/// The widget's one setting, "Tool" (right-click the widget, Edit Widget).
enum ToolOption: String, AppEnum {
    case claudeCode, codex, all

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tool"
    static let caseDisplayRepresentations: [ToolOption: DisplayRepresentation] = [
        .claudeCode: "Claude Code",
        .codex: "Codex",
        .all: "All tools",
    ]

    var widgetTool: WidgetTool {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .all: .all
        }
    }
}

struct ToolSelection: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tool"
    static let description = IntentDescription("Choose which tool's limits the widget shows.")

    /// Claude Code by default, so widgets placed with Wiggleroom 0.1 keep showing what they showed.
    @Parameter(title: "Tool", default: .claudeCode)
    var tool: ToolOption
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        // Same kind as 0.1's widget, so widgets already placed keep working (with the default Tool).
        AppIntentConfiguration(kind: "WiggleroomUsage", intent: ToolSelection.self, provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Wiggleroom")
        .description("How much of your AI coding plans you've used, and when the limits reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let choice: WidgetTool
    let tools: [ToolSnapshot]
    let groupAvailable: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        sample(Date(), choice: .claudeCode)
    }

    func snapshot(for configuration: ToolSelection, in context: Context) async -> Entry {
        let now = Date()
        let tools = load(now)
        // The widget gallery shows invented numbers until there are real ones.
        if context.isPreview, tools.isEmpty { return sample(now, choice: configuration.tool.widgetTool) }
        return Entry(date: now, choice: configuration.tool.widgetTool, tools: tools, groupAvailable: AppGroupFiles.folder() != nil)
    }

    func timeline(for configuration: ToolSelection, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let tools = load(now)
        let group = AppGroupFiles.folder() != nil
        // One entry now, at each reset, at local midnight, and every 15 minutes for the
        // "as of" color. The countdown text ticks on its own between entries.
        let entries = TimelinePlan.dates(for: tools.map(\.usage), now: now).map {
            Entry(date: $0, choice: configuration.tool.widgetTool, tools: tools, groupAvailable: group)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// Every tool's snapshot from the App Group (0.1's file is read as Claude Code).
    private func load(_ now: Date) -> [ToolSnapshot] {
        guard let folder = AppGroupFiles.folder() else { return [] }
        return AppGroupFiles.readTools(in: folder, now: now)
    }

    private func sample(_ now: Date, choice: WidgetTool) -> Entry {
        Entry(date: now, choice: choice, tools: [ToolSnapshot(tool: .claudeCode, usage: SampleData.snapshot(now: now, age: 60))], groupAvailable: true)
    }
}

struct UsageWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let content = WidgetContent.make(choice: entry.choice, tools: entry.tools, groupAvailable: entry.groupAvailable,
                                         context: DisplayContext(now: entry.date))
        WidgetCard(content: content, layout: family == .systemSmall ? .small : .medium, live: true)
            .containerBackground(for: .widget) { Palette(scheme).card }
    }
}
