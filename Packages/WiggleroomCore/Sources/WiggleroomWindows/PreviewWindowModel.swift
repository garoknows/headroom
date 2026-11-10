import WiggleroomCore
import WiggleroomUI
import SwiftUI

/// A stand-in for the app's model with invented numbers and no side effects: every action does
/// nothing. The docs renders and the layout tests use it to draw the real windows.
@MainActor
public final class PreviewWindowModel: WindowModel {
    @Published public var connection: ClaudeSettingsEditor.Status
    @Published public var lastMessage: String?
    @Published public var canShareWithWidget: Bool
    @Published public var display: UsageDisplay?
    @Published public var isWatching = true
    @Published public var notificationsAllowed: Bool?
    @Published public var launchAtLogin = true
    @Published public var alerts: AlertSettings = .default
    @Published public var showMenuBar = true
    @Published public var menuBarChoice: MenuBarChoice = .default
    @Published public var codexConnected = false
    @Published public var codexInstalled = true
    @Published public var codexStatusText = "Not connected"
    @Published public var codexDisplay: UsageDisplay?
    public var setupDone = false
    public let version = "0.1.1 (2)"

    public init(connection: ClaudeSettingsEditor.Status = .notConnected(hasOtherStatusLine: false),
                lastMessage: String? = nil, canShareWithWidget: Bool = true,
                display: UsageDisplay? = nil, notificationsAllowed: Bool? = true) {
        self.connection = connection
        self.lastMessage = lastMessage
        self.canShareWithWidget = canShareWithWidget
        self.display = display
        self.notificationsAllowed = notificationsAllowed
    }

    public var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }
    public var connectedElsewhere: Bool { false }
    public var cardContent: CardContent { display.map { .usage($0) } ?? .empty }
    public var toolDisplays: [ToolDisplay] {
        var out: [ToolDisplay] = []
        if let display { out.append(ToolDisplay(tool: .claudeCode, display: display)) }
        if codexConnected, let codexDisplay { out.append(ToolDisplay(tool: .codex, display: codexDisplay)) }
        return ToolDisplay.closestFirst(out)
    }
    public var connectedTools: [Tool] {
        (isConnected || display != nil ? [Tool.claudeCode] : []) + (codexConnected ? [.codex] : [])
    }

    public var watcherText: String { isWatching ? "Watching for new numbers from Claude Code" : "Not watching: the data folder can't be read" }

    public func connect() {}
    public func disconnect() {}
    public func refreshConnection() {}
    public func refreshNotificationPermission() {}
    public func setLaunchAtLogin(_ on: Bool) {}
    public func revealDataFile() {}
    public func deleteAllData() {}
    public func openNotificationSettings() {}
    public func quit() {}
    public func connectCodex() {}
    public func disconnectCodex() {}
    public func checkCodexAgain() {}
}

/// Invented situations for the renders and the layout tests, all at one fixed moment:
/// Thursday Jan 14, 2027, 2:45 PM in Las Vegas, 12-hour clock.
@MainActor
public enum PreviewStates {
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    public static let now: Date = {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 14, minute: 45))!
    }()
    public static let context = DisplayContext(now: now, timeZone: timeZone, clock: .twelveHour)

    /// A plan with both limits (5-hour session and weekly).
    public static var bothLimits: UsageDisplay {
        UsageFormatter.display(SampleData.snapshot(now: now, timeZone: timeZone, age: 4 * 60), context: context)
    }

    /// A plan that reports only the weekly limit.
    public static var weeklyOnly: UsageDisplay {
        var s = SampleData.snapshot(now: now, timeZone: timeZone, age: 3 * 60)
        s.limits.removeFirst()
        return UsageFormatter.display(s, context: context)
    }

    /// Invented Codex numbers: 5-hour 12%, this week 64%.
    public static var codexUsage: UsageSnapshot {
        UsageSnapshot(updatedAt: now.addingTimeInterval(-2 * 60), limits: [
            LimitWindow(id: LimitKind.session, usedPercent: 12, resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60), label: "5-hour", windowMinutes: 300),
            LimitWindow(id: LimitKind.weekly, usedPercent: 64, resetsAt: SampleData.snapshot(now: now, timeZone: timeZone).limits[1].resetsAt, label: "This week", windowMinutes: 10080),
        ])
    }

    public static var codex: UsageDisplay { UsageFormatter.display(codexUsage, context: context) }

    /// The longest message Connect can show, with a long file path that has no spaces to wrap at.
    public static let longConnectMessage = "Connected. Wiggleroom replaced the Headroom preview in your status line setting. Your own status line still runs after Wiggleroom. A backup of your previous settings is at ~/Library/Application_Support/io.github.garoknows.wiggleroom/settings-backups/settings-2027-01-14T22-45-00Z-an-invented-very-long-file-name.json."

    static let helper = "/Applications/Wiggleroom.app/Contents/MacOS/wiggleroom-statusline"

    /// The window states worth looking at, by name.
    /// Tools connected: 0 ("first-run"), 1 ("connected", Claude Code only), 2 ("two-tools"),
    /// plus Codex missing and the longest Codex message.
    public static func models() -> [(String, PreviewWindowModel)] {
        let claude = ClaudeSettingsEditor.Status.connected(StatuslineCommand(executablePath: helper, previous: "bash ~/.claude/statusline.sh"))
        let firstRun = PreviewWindowModel(connection: .notConnected(hasOtherStatusLine: false), display: nil, notificationsAllowed: nil)
        let one = PreviewWindowModel(connection: claude, lastMessage: longConnectMessage, display: weeklyOnly)
        let two = PreviewWindowModel(connection: claude, display: bothLimits)
        two.codexConnected = true
        two.codexDisplay = codex
        two.codexStatusText = "Connected"
        two.menuBarChoice = .highest
        let noCodex = PreviewWindowModel(connection: claude, display: weeklyOnly)
        noCodex.codexInstalled = false
        noCodex.codexStatusText = CodexStatusText.notFound
        let unsigned = PreviewWindowModel(connection: .notConnected(hasOtherStatusLine: true), canShareWithWidget: false,
                                          display: bothLimits, notificationsAllowed: false)
        unsigned.codexConnected = true
        unsigned.codexStatusText = CodexStatusText.noPlanLimits
        return [("first-run", firstRun), ("connected", one), ("two-tools", two), ("codex-not-found", noCodex), ("unsigned-alerts-off", unsigned)]
    }
}
