import WiggleroomCore
import WiggleroomUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let openSetup: () -> Void
    @State private var confirmDelete = false
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section("Claude Code") {
                ConnectionStatusRow(model: model)
                HStack {
                    if model.isConnected && !model.connectedElsewhere {
                        Button("Disconnect…") { confirmDisconnect = true }
                    } else {
                        Button(model.connectedElsewhere ? "Update Connection" : "Connect to Claude Code") {
                            model.connect()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                if let message = model.lastMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            Section("Status") {
                Label(model.watcherText, systemImage: model.watcherState == .watching ? "checkmark.circle" : "exclamationmark.triangle")
                Text(model.display?.asOfText ?? "No numbers from Claude Code yet. They arrive with your next Claude Code reply.")
                    .foregroundStyle(.secondary)
                if model.groupFolder == nil {
                    Label("This copy of Wiggleroom isn't signed, so it can't share numbers with widgets. The menu bar item still works. Install the signed release to use the widget.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Alerts") {
                Toggle("Alert me about my weekly limit", isOn: $model.alerts.enabled)
                ForEach(AlertSettings.choices, id: \.self) { level in
                    Toggle("When I pass \(level)%", isOn: Binding(
                        get: { model.alerts.thresholds.contains(level) },
                        set: { on in
                            var t = Set(model.alerts.thresholds)
                            if on { t.insert(level) } else { t.remove(level) }
                            model.alerts = AlertSettings(enabled: model.alerts.enabled, thresholds: Array(t))
                        }))
                    .disabled(!model.alerts.enabled)
                    .padding(.leading, 18)
                }
                if model.alerts.enabled && model.notificationsAllowed == false {
                    HStack {
                        Text("Notifications for Wiggleroom are turned off in System Settings.").foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(u) }
                        }
                    }
                }
                Text("At most one alert per level each week, and only from fresh numbers.").font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Show in the menu bar", isOn: $model.showMenuBar)
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Button("Show How to Add the Widget…", action: openSetup)
            }

            Section("Your data") {
                Text("Wiggleroom keeps only the percent used, the reset times, the limit names and when they were updated. It has no network code and never reads your Claude sign-in.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reveal Data File") { model.revealDataFile() }
                    Spacer()
                    Button("Delete All Wiggleroom Data…", role: .destructive) { confirmDelete = true }
                }
            }

            Section {
                HStack {
                    Text("Wiggleroom \(model.version)").foregroundStyle(.secondary)
                    Spacer()
                    Link("Help and source code", destination: URL(string: "https://github.com/garoknows/wiggleroom")!)
                }
                HStack {
                    Text("Wiggleroom runs in the background to keep the widget up to date.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Wiggleroom") { NSApp.terminate(nil) }
                }
                Text("An independent open-source project. Not made by or affiliated with Anthropic.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
        .onAppear { model.refreshConnection(); model.refreshNotificationPermission() }
        .confirmationDialog("Disconnect Wiggleroom from Claude Code?", isPresented: $confirmDisconnect) {
            Button("Disconnect") { model.disconnect() }
        } message: {
            Text("Your previous status line setting is put back. The widget keeps showing the last numbers it has.")
        }
        .confirmationDialog("Delete all Wiggleroom data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.deleteAllData() }
        } message: {
            Text("This disconnects Wiggleroom from Claude Code (your previous status line comes back), deletes the saved numbers and the widget's copy, and resets Wiggleroom's settings. Backups of your Claude Code settings are kept.")
        }
    }
}

struct ConnectionStatusRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.connection {
        case .connected(let c):
            if model.connectedElsewhere {
                Label("Connected, but to a copy of Wiggleroom in another place. Click Update Connection.", systemImage: "exclamationmark.triangle")
            } else {
                Label(c.previous == nil ? "Connected" : "Connected. Your own status line still runs after Wiggleroom.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .notConnected(let other):
            Label(other ? "Not connected. You have your own status line; Wiggleroom will keep it working." : "Not connected", systemImage: "circle")
        case .noSettingsFile:
            Label("Not connected. Claude Code has no settings file yet; Wiggleroom will create one.", systemImage: "circle")
        case .unreadable(let r):
            Label(r.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}
