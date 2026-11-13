import WiggleroomCore
import WiggleroomUI
import SwiftUI

public struct SettingsView<Model: WindowModel>: View {
    @ObservedObject var model: Model
    let openSetup: () -> Void
    @State private var confirmDelete = false
    @State private var confirmDisconnect = false

    public init(model: Model, openSetup: @escaping () -> Void) {
        self.model = model
        self.openSetup = openSetup
    }

    var codexSymbol: String {
        if !model.codexInstalled { return "questionmark.circle" }
        if !model.codexConnected { return "circle" }
        return model.codexStatusText == "Connected" ? "checkmark.circle.fill" : "clock"
    }

    public var body: some View {
        // Sections laid out by Wiggleroom itself (0.1.0 used a grouped Form, whose width and
        // margins depend on the Xcode version that built the app and on the scroll bar setting).
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection("Tools") {
                    ToolRow("Claude Code") {
                        if model.isConnected && !model.connectedElsewhere {
                            Button("Disconnect…") { confirmDisconnect = true }
                        } else {
                            Button(model.connectedElsewhere ? "Update Connection" : "Connect") {
                                model.connect()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } status: {
                        ConnectionStatusRow(model: model).wrapping()
                        if let message = model.lastMessage {
                            Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                .wrapping()
                        }
                    }
                    .layoutProbe("settings: Claude Code row")
                    Divider()
                    ToolRow("Codex") {
                        if model.codexConnected {
                            Button("Disconnect") { model.disconnectCodex() }
                        } else if model.codexInstalled {
                            Button("Connect") { model.connectCodex() }.buttonStyle(.borderedProminent)
                        } else {
                            Button("Check Again") { model.checkCodexAgain() }
                        }
                    } status: {
                        Label(model.codexStatusText, systemImage: codexSymbol)
                            .foregroundStyle(model.codexConnected && model.codexStatusText == "Connected" ? Color.green : Color.secondary)
                            .wrapping()
                        if model.codexConnected {
                            Text("Wiggleroom reads only the usage numbers from the end of Codex's newest session log. It changes nothing in Codex.")
                                .font(.caption).foregroundStyle(.secondary).wrapping()
                        }
                    }
                    .layoutProbe("settings: Codex row")
                    Divider()
                    Text(.init("More tools: Wiggleroom adds a tool when it offers an official way to read its limits. [See which are coming.](https://github.com/garoknows/wiggleroom/blob/main/docs/TOOLS.md)"))
                        .font(.caption).foregroundStyle(.secondary).wrapping()
                }

                SettingsSection("Status") {
                    // The same watcher lines as the popover's footer (0.2.2).
                    ForEach(Array(model.watcherLines.enumerated()), id: \.offset) { i, line in
                        Label(line.text, systemImage: line.ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .wrapping()
                            .layoutProbe("settings: watcher line \(i)")
                    }
                    Text(model.display.map { "Claude Code: \($0.asOfText)" } ?? "No numbers from Claude Code yet. They arrive with your next Claude Code reply.")
                        .foregroundStyle(.secondary)
                        .wrapping()
                    if let codex = model.toolDisplays.first(where: { $0.tool == .codex }) {
                        Text("Codex: \(codex.display.asOfText)").foregroundStyle(.secondary).wrapping()
                    }
                    if !model.canShareWithWidget {
                        Label("This copy of Wiggleroom isn't signed, so it can't share numbers with widgets. The menu bar item still works. Install the signed release to use the widget.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .wrapping()
                    }
                }

                SettingsSection("Alerts") {
                    SwitchRow("Alert me when a tool nears a limit", isOn: $model.alerts.enabled)
                        .layoutProbe("settings: alerts toggle")
                    ForEach(AlertSettings.choices, id: \.self) { level in
                        SwitchRow("When I pass \(level)%", isOn: Binding(
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
                        HStack(alignment: .firstTextBaseline) {
                            Text("Notifications for Wiggleroom are turned off in System Settings.").foregroundStyle(.secondary)
                                .wrapping()
                            Spacer(minLength: 8)
                            Button("Open Settings") { model.openNotificationSettings() }
                        }
                        .layoutProbe("settings: notifications off row")
                    }
                    Text("For every connected tool and every limit (5-hour and weekly). At most one alert per level, per tool, per limit, and only from fresh numbers.").font(.caption).foregroundStyle(.secondary)
                        .wrapping()
                }

                SettingsSection("General") {
                    SwitchRow("Show in the menu bar", isOn: $model.showMenuBar)
                    HStack {
                        Text("Menu bar shows").wrapping()
                        Spacer(minLength: 8)
                        Picker("Menu bar shows", selection: $model.menuBarChoice) {
                            ForEach(MenuBarChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .disabled(!model.showMenuBar)
                    .layoutProbe("settings: menu bar picker")
                    SwitchRow("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                        .layoutProbe("settings: Open at login toggle")
                    Button("Show How to Add the Widget…", action: openSetup)
                }

                SettingsSection("Your data") {
                    Text("Wiggleroom keeps only the percent used, the reset times, the limit names and when they were updated, for each tool. It has no network code and never reads your Claude or Codex sign-in.")
                        .foregroundStyle(.secondary)
                        .wrapping()
                    HStack {
                        Button("Reveal Data File") { model.revealDataFile() }
                        Spacer(minLength: 8)
                        Button("Delete All Wiggleroom Data…", role: .destructive) { confirmDelete = true }
                    }
                    .layoutProbe("settings: data buttons")
                }

                SettingsSection(nil) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Wiggleroom \(model.version)").foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Link("Help and source code", destination: URL(string: "https://github.com/garoknows/wiggleroom")!)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Wiggleroom runs in the background to keep the widget up to date.").font(.caption).foregroundStyle(.secondary)
                            .wrapping()
                        Spacer(minLength: 8)
                        Button("Quit Wiggleroom") { model.quit() }
                    }
                    .layoutProbe("settings: Quit row")
                    Text("An independent open-source project. Not made by or affiliated with Anthropic.")
                        .font(.caption).foregroundStyle(.secondary)
                        .wrapping()
                }
            }
            // Measured inside the padding: the sections themselves must fit what the window shows.
            .layoutProbe("settings: content")
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: WindowSizes.settings.width, height: WindowSizes.settings.height)
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

struct ConnectionStatusRow<Model: WindowModel>: View {
    @ObservedObject var model: Model

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

/// A titled group of rows on a rounded background, like System Settings.
struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline).padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background.secondary))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.separator, lineWidth: 0.5))
        }
    }
}

/// A setting with its name on the left and a switch on the right. The name wraps if it's long.
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).wrapping()
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

extension View {
    /// Text that wraps onto more lines instead of making its row wider.
    func wrapping() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}

/// One tool in the Tools section: its name, its one button on the right, its status below.
struct ToolRow<Action: View, Status: View>: View {
    let name: String
    let button: Action
    let status: Status

    init(_ name: String, @ViewBuilder button: () -> Action, @ViewBuilder status: () -> Status) {
        self.name = name
        self.button = button()
        self.status = status()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(name).font(.body.weight(.semibold)).wrapping()
                Spacer(minLength: 0)
                button
            }
            status
        }
    }
}
