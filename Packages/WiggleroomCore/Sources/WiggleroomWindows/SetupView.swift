import WiggleroomCore
import WiggleroomUI
import SwiftUI

/// The first-run window: connect, add the widget (with annotated pictures), choose options.
public struct SetupView<Model: WindowModel>: View {
    @ObservedObject var model: Model
    let done: () -> Void
    /// The invented numbers in the widget gallery picture (fixed in renders and tests).
    let fixedSample: UsageDisplay?
    @State private var openAtLogin = true

    public init(model: Model, sample: UsageDisplay? = nil, done: @escaping () -> Void) {
        self.model = model
        self.fixedSample = sample
        self.done = done
    }

    var sample: UsageDisplay {
        fixedSample ?? UsageFormatter.display(SampleData.snapshot(now: Date(), age: 60), context: DisplayContext(now: Date()))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    WiggleroomMark().frame(width: 52, height: 52).layoutProbe("setup: title icon")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to Wiggleroom").font(.title.bold())
                        Text("See how much of your Claude plan you've used, right in Notification Center.").foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                step(1, "Connect to Claude Code") {
                    Text("Claude Code hands your plan's usage to its status line after every reply. Wiggleroom adds a small helper there that saves just those numbers, then runs your existing status line exactly as before. Your Claude Code settings are backed up first, and Disconnect puts them back.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if model.isConnected && !model.connectedElsewhere {
                            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Connect to Claude Code") { model.connect() }.buttonStyle(.borderedProminent).layoutProbe("setup: Connect button")
                        }
                    }
                    if let m = model.lastMessage {
                        Text(m).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Then send any message in Claude Code. The numbers appear after its reply.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                step(2, "Add the widget to Notification Center") {
                    caption(1, "Click the date and time at the right end of the menu bar.")
                    FitToWidth(MenuBarPicture.size, probe: "setup: picture 1") { MenuBarPicture() }
                    caption(2, "Scroll to the bottom of Notification Center and click Edit Widgets.")
                    FitToWidth(NotificationCenterPicture.size, probe: "setup: picture 2") { NotificationCenterPicture() }
                    caption(3, "Type Wiggleroom in the search field.")
                    caption(4, "Pick a size, then click the green + (or drag the widget into Notification Center). Click Done.")
                    FitToWidth(WidgetGalleryPicture.size, probe: "setup: picture 3") { WidgetGalleryPicture(sample: sample) }
                    if !model.canShareWithWidget {
                        Label("This copy of Wiggleroom isn't signed, so its widget can't receive numbers. Use the menu bar item instead, or install the signed release.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                step(3, "Options") {
                    Toggle("Alert me when I pass 90% of my weekly limit", isOn: $model.alerts.enabled)
                    Toggle("Show my weekly percent in the menu bar", isOn: $model.showMenuBar)
                    Toggle("Open Wiggleroom at login (it keeps the widget up to date)", isOn: $openAtLogin)
                }

                HStack {
                    Spacer()
                    Button("Done") {
                        if openAtLogin != model.launchAtLogin { model.setLaunchAtLogin(openAtLogin) }
                        model.setupDone = true
                        if model.alerts.enabled { model.refreshNotificationPermission() }   // asks macOS once if needed
                        done()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            // Measured inside the padding: the content itself must fit what the window shows.
            .layoutProbe("setup: content")
            .padding(28)
            // Leading-aligned at the window's width, so a child that is ever too wide sticks out
            // on the right (and fails the layout test) instead of shifting everything left.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: WindowSizes.setup.width, height: WindowSizes.setup.height)
        .onAppear { model.refreshConnection() }
    }

    func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(n)").font(.headline).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(Color.accentColor))
                Text(title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    func caption(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StepMarker(n)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
