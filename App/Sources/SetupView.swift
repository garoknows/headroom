import WiggleroomCore
import WiggleroomUI
import SwiftUI

/// The first-run window: connect, add the widget (with annotated pictures), choose options.
struct SetupView: View {
    @ObservedObject var model: AppModel
    let done: () -> Void
    @State private var openAtLogin = true

    var sample: UsageDisplay {
        UsageFormatter.display(SampleData.snapshot(now: Date(), age: 60), context: DisplayContext(now: Date()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    WiggleroomMark().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to Wiggleroom").font(.title.bold())
                        Text("See how much of your Claude plan you've used, right in Notification Center.").foregroundStyle(.secondary)
                    }
                }

                step(1, "Connect to Claude Code") {
                    Text("Claude Code hands your plan's usage to its status line after every reply. Wiggleroom adds a small helper there that saves just those numbers, then runs your existing status line exactly as before. Your Claude Code settings are backed up first, and Disconnect puts them back.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if model.isConnected && !model.connectedElsewhere {
                            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Connect to Claude Code") { model.connect() }.buttonStyle(.borderedProminent)
                        }
                    }
                    if let m = model.lastMessage { Text(m).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                    Text("Then send any message in Claude Code. The numbers appear after its reply.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                step(2, "Add the widget to Notification Center") {
                    caption(1, "Click the date and time at the right end of the menu bar.")
                    MenuBarPicture()
                    caption(2, "Scroll to the bottom of Notification Center and click Edit Widgets.")
                    NotificationCenterPicture()
                    caption(3, "Type Wiggleroom in the search field.")
                    caption(4, "Pick a size, then click the green + (or drag the widget into Notification Center). Click Done.")
                    WidgetGalleryPicture(sample: sample).scaleEffect(0.82, anchor: .topLeading).frame(height: 232, alignment: .topLeading)
                    if model.groupFolder == nil {
                        Label("This copy of Wiggleroom isn't signed, so its widget can't receive numbers. Use the menu bar item instead, or install the signed release.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
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
            .padding(28)
        }
        .frame(width: 620, height: 720)
        .onAppear { model.refreshConnection() }
    }

    func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(n)").font(.headline).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(Color.accentColor))
                Text(title).font(.title3.bold())
            }
            content()
        }
    }

    func caption(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StepMarker(n)
            Text(text)
        }
    }
}
