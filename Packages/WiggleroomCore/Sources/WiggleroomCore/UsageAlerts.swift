import Foundation

/// The user's choices for weekly usage alerts.
public struct AlertSettings: Codable, Equatable, Sendable {
    /// The master switch. On by default.
    public var enabled: Bool
    /// Percent levels to alert at. Default: 90 only. 75 can be turned on in Settings.
    public var thresholds: [Int]

    public static let `default` = AlertSettings(enabled: true, thresholds: [90])
    public static let choices = [75, 90]

    public init(enabled: Bool, thresholds: [Int]) {
        self.enabled = enabled
        self.thresholds = thresholds.filter { (1...100).contains($0) }.sorted()
    }
}

/// Which alerts already went out: for each threshold, the reset time of the week it fired in.
public struct AlertRecord: Codable, Equatable, Sendable {
    /// Key: "<tool>|<limit id>|<threshold>", value: the reset time of the window it fired in.
    public var fired: [String: Date]
    public init(fired: [String: Date] = [:]) { self.fired = fired }

    public static func key(_ tool: Tool, _ limit: String, _ threshold: Int) -> String { "\(tool.rawValue)|\(limit)|\(threshold)" }

    /// 0.1 kept only Claude Code's weekly alerts, keyed by the threshold alone ("90"). They
    /// become Claude Code weekly keys, so an alert already sent this week isn't sent again.
    public func migrated() -> AlertRecord {
        var out: [String: Date] = [:]
        for (k, v) in fired {
            if k.contains("|") { out[k] = v } else if let t = Int(k) { out[Self.key(.claudeCode, LimitKind.weekly, t)] = v }
        }
        return AlertRecord(fired: out)
    }
}

public struct UsageAlert: Equatable, Sendable {
    public var tool: Tool
    public var limitID: String
    /// How the limit is named in the text: "weekly", "5-hour", "3-day"…
    public var limitName: String
    public var threshold: Int
    public var percent: Int
    public var resetsAt: Date

    /// "Codex: 90% of your weekly limit used."
    public var title: String { "\(tool.displayName): \(percent)% of your \(limitName) limit used." }

    /// "Resets Monday 1:00 AM."
    public func body(context: DisplayContext) -> String {
        "Resets \(UsageFormatter.moment(resetsAt, context: context, short: false))."
    }

    /// One notification per tool and limit, so a newer one replaces an older one for the same limit.
    public var identifier: String { "\(tool.rawValue)-\(limitID)" }

    static func name(for limit: LimitWindow) -> String {
        switch limit.id {
        case LimitKind.weekly: return "weekly"
        case LimitKind.session: return "5-hour"
        case LimitKind.spend: return "spend"
        default:
            if let m = limit.windowMinutes { return WindowNaming.label(windowMinutes: m) }
            return (limit.label ?? UsageFormatter.title(for: limit.id)).lowercased()
        }
    }
}

/// Decides when to send alerts: for every tool and every limit, at most once per threshold per
/// window (a window is one stretch between resets).
public enum AlertPlanner {
    /// Two reset times this close together belong to the same window (the reported value can
    /// move by a few seconds between replies).
    static let sameWindow: TimeInterval = 3600

    /// Returns the alerts to send now and the updated record to save. Several thresholds crossed
    /// at once give one alert per limit, for the highest. Nothing is sent from numbers that are
    /// 6 hours old or from a window that already reset (lesson 7: unknown means do nothing).
    public static func evaluate(tools: [ToolSnapshot], settings: AlertSettings, record: AlertRecord,
                                now: Date) -> (alerts: [UsageAlert], record: AlertRecord) {
        var record = record.migrated()
        // Forget windows that ended more than a day ago.
        record.fired = record.fired.filter { now.timeIntervalSince($0.value) < 24 * 3600 }
        guard settings.enabled else { return ([], record) }
        var alerts: [UsageAlert] = []
        for t in tools where Freshness.of(updatedAt: t.usage.updatedAt, now: now) != .veryStale {
            for limit in t.usage.limits {
                guard let reset = limit.resetsAt, reset > now else { continue }
                var highest: Int?
                for threshold in settings.thresholds where limit.usedPercent >= Double(threshold) {
                    let key = AlertRecord.key(t.tool, limit.id, threshold)
                    if let done = record.fired[key], abs(done.timeIntervalSince(reset)) < sameWindow { continue }
                    record.fired[key] = reset
                    highest = max(highest ?? threshold, threshold)
                }
                if let highest {
                    alerts.append(UsageAlert(tool: t.tool, limitID: limit.id, limitName: UsageAlert.name(for: limit), threshold: highest,
                                             percent: UsageFormatter.wholePercent(limit.usedPercent), resetsAt: reset))
                }
            }
        }
        return (alerts, record)
    }
}
