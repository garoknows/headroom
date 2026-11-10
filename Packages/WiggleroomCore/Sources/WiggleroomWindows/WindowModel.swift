import WiggleroomCore
import WiggleroomUI
import SwiftUI

/// What the setup window, the Settings window and the menu bar popover read and do.
/// The app's AppModel provides the real one. The docs renders and the layout tests use an
/// invented one, so every window can be drawn and measured at its real size without the app.
@MainActor
public protocol WindowModel: ObservableObject {
    var connection: ClaudeSettingsEditor.Status { get }
    var isConnected: Bool { get }
    /// True when the setting points at a Wiggleroom in another place (the app was moved).
    var connectedElsewhere: Bool { get }
    var lastMessage: String? { get }
    /// False in unsigned builds, which have no App Group to share numbers with the widget.
    var canShareWithWidget: Bool { get }
    var display: UsageDisplay? { get }
    var cardContent: CardContent { get }
    var isWatching: Bool { get }
    var watcherText: String { get }
    var notificationsAllowed: Bool? { get }
    var launchAtLogin: Bool { get }
    var version: String { get }
    var alerts: AlertSettings { get set }
    var showMenuBar: Bool { get set }
    var setupDone: Bool { get set }
    var menuBarChoice: MenuBarChoice { get set }

    // Codex (0.2)
    var codexConnected: Bool { get }
    var codexInstalled: Bool { get }
    var codexStatusText: String { get }
    /// Every connected tool with numbers, closest to a limit first.
    var toolDisplays: [ToolDisplay] { get }
    /// Connected tools, with or without numbers yet.
    var connectedTools: [Tool] { get }

    func connect()
    func disconnect()
    func refreshConnection()
    func refreshNotificationPermission()
    func setLaunchAtLogin(_ on: Bool)
    func revealDataFile()
    func deleteAllData()
    func openNotificationSettings()
    func quit()
    func connectCodex()
    func disconnectCodex()
    func checkCodexAgain()
}

/// The real sizes of Wiggleroom's windows, in one place so the app, the renders and the layout
/// tests all use the same numbers.
public enum WindowSizes {
    public static let setup = CGSize(width: 620, height: 720)
    public static let settings = CGSize(width: 520, height: 640)
    public static let popoverWidth: CGFloat = 320
}
