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
    public var threshold: Int
    public var percent: Int
    public var resetsAt: Date
    public var title: String { "You've used \(percent)% of this week's Claude limit" }

    public func body(context: DisplayContext) -> String {
        "It resets \(UsageFormatter.moment(resetsAt, context: context, short: false))."
    }
}

/// Decides when to send an alert. Only the weekly limit, at most once per threshold per week.
public enum AlertPlanner {
    /// Two reset times this close together belong to the same week (Claude Code's value can
    /// move by a few seconds between replies).
    static let sameWindow: TimeInterval = 3600

    /// Returns the alert to send now (if any) and the updated record to save.
    /// Several thresholds crossed at once give one alert, for the highest.
    /// Nothing is sent from numbers that are 6 hours old or whose week already reset.
    public static func evaluate(snapshot: UsageSnapshot?, settings: AlertSettings, record: AlertRecord,
                                now: Date) -> (alert: UsageAlert?, record: AlertRecord) {
        var record = record
        // Forget weeks that ended more than a day ago.
        record.fired = record.fired.filter { now.timeIntervalSince($0.value) < 24 * 3600 }
        guard settings.enabled, let snapshot, let week = snapshot.limit(LimitKind.weekly),
              let reset = week.resetsAt, reset > now,
              Freshness.of(updatedAt: snapshot.updatedAt, now: now) != .veryStale else { return (nil, record) }
        var highest: Int?
        for t in settings.thresholds where week.usedPercent >= Double(t) {
            let key = String(t)
            if let done = record.fired[key], abs(done.timeIntervalSince(reset)) < sameWindow { continue }
            record.fired[key] = reset
            highest = max(highest ?? t, t)
        }
        guard let highest else { return (nil, record) }
        return (UsageAlert(threshold: highest, percent: UsageFormatter.wholePercent(week.usedPercent), resetsAt: reset), record)
    }
}
