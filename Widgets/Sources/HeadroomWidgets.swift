import HeadroomCore
import HeadroomUI
import SwiftUI
import WidgetKit

// The Headroom widget. It reads one small file in the App Group folder that the Headroom app
// writes, and nothing else: no network, no Keychain, no other files (lesson 10).

@main
struct HeadroomWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeadroomUsage", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("Your Claude plan usage and when it resets.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let content: CardContent
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        sample(Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let now = Date()
        // The widget gallery shows invented numbers until there are real ones.
        if context.isPreview, load(now) == nil { completion(sample(now)); return }
        completion(entry(now, snapshot: load(now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = load(now)
        // One entry now, at each reset, at local midnight, and every 15 minutes for the
        // "as of" color. The countdown text ticks on its own between entries.
        let entries = TimelinePlan.dates(for: snapshot, now: now).map { entry($0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// The App Group snapshot, or nil. A missing group means this build can't share data.
    private func load(_ now: Date) -> UsageSnapshot? {
        guard let folder = AppGroupFiles.folder() else { return nil }
        return AppGroupFiles.readSnapshot(in: folder, now: now)
    }

    private func entry(_ date: Date, snapshot: UsageSnapshot?) -> Entry {
        if let snapshot {
            return Entry(date: date, content: .usage(UsageFormatter.display(snapshot, context: DisplayContext(now: date))))
        }
        return Entry(date: date, content: AppGroupFiles.folder() == nil ? .unavailable : .empty)
    }

    private func sample(_ now: Date) -> Entry {
        Entry(date: now, content: .usage(UsageFormatter.display(SampleData.snapshot(now: now, age: 60), context: DisplayContext(now: now))))
    }
}

struct UsageWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        UsageCard(content: entry.content, layout: family == .systemSmall ? .small : .medium, live: true)
            .containerBackground(for: .widget) { Palette(scheme).card }
    }
}
