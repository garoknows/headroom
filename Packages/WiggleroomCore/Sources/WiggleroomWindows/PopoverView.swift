import WiggleroomCore
import WiggleroomUI
import SwiftUI

/// The menu bar item's popover: one block per connected tool (closest to a limit first), the
/// watcher state, Settings… and Quit.
public struct PopoverView<Model: WindowModel>: View {
    @ObservedObject var model: Model
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(model: Model, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    /// Connected tools that have no numbers yet.
    var waitingTools: [Tool] {
        model.connectedTools.filter { t in !model.toolDisplays.contains { $0.tool == t } }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if model.toolDisplays.isEmpty && model.connectedTools.isEmpty {
                    UsageCard(content: model.cardContent, layout: .popover, live: true)
                } else {
                    ToolBlocks(tools: model.toolDisplays, waiting: waitingTools, live: true)
                }
            }
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
