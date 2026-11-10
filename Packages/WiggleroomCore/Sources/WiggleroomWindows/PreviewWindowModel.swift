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

    /// The longest message Connect can show, with a long file path that has no spaces to wrap at.
    public static let longConnectMessage = "Connected. Wiggleroom replaced the Headroom preview in your status line setting. Your own status line still runs after Wiggleroom. A backup of your previous settings is at ~/Library/Application_Support/io.github.garoknows.wiggleroom/settings-backups/settings-2027-01-14T22-45-00Z-an-invented-very-long-file-name.json."

    static let helper = "/Applications/Wiggleroom.app/Contents/MacOS/wiggleroom-statusline"

    /// The window states worth looking at, by name.
    public static func models() -> [(String, PreviewWindowModel)] {
        [
            ("first-run", PreviewWindowModel(connection: .notConnected(hasOtherStatusLine: false), display: nil, notificationsAllowed: nil)),
            ("connected", PreviewWindowModel(connection: .connected(StatuslineCommand(executablePath: helper, previous: "bash ~/.claude/statusline.sh")),
                                             lastMessage: longConnectMessage, display: weeklyOnly)),
            ("unsigned-alerts-off", PreviewWindowModel(connection: .notConnected(hasOtherStatusLine: true), canShareWithWidget: false,
                                                       display: bothLimits, notificationsAllowed: false)),
        ]
    }
}
