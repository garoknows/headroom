import WiggleroomCore
import WiggleroomUI
import SwiftUI

/// The menu bar item's popover: the card, the watcher state, Settings… and Quit.
public struct PopoverView<Model: WindowModel>: View {
    @ObservedObject var model: Model
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(model: Model, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageCard(content: model.cardContent, layout: .popover, live: true)
                .layoutProbe("popover: card")
            Divider()
            Label(model.watcherText, systemImage: model.isWatching ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Quit Wiggleroom") { model.quit() }
            }
        }
        .padding(16)
        .frame(width: WindowSizes.popoverWidth)
        // As tall as the content, never taller: one row and no gap for a weekly-only plan.
        .fixedSize(horizontal: false, vertical: true)
        .layoutProbe("popover: content")
        .background(Palette(scheme).card)
    }
}
