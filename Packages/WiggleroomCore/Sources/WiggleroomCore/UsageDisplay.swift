import Foundation

/// 12-hour ("1:00 AM") or 24-hour ("01:00") clock.
public enum ClockStyle: Sendable, Equatable {
    case twelveHour, twentyFourHour

    /// The style the user picked in System Settings (Language & Region), read from their locale.
    public static func current(locale: Locale = .autoupdatingCurrent) -> ClockStyle {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        // Drop quoted literal text first (German gives "HH 'Uhr'", and "Uhr" has an h in it).
        let symbols = pattern.split(separator: "'", omittingEmptySubsequences: false)
            .enumerated().filter { $0.offset % 2 == 0 }.map(\.element).joined()
        return symbols.contains("h") || symbols.contains("K") || symbols.contains("a") ? .twelveHour : .twentyFourHour
    }
}

/// Everything formatting depends on, passed in so tests can pin the time zone, clock and "now".
public struct DisplayContext: Sendable {
    public var now: Date
    public var timeZone: TimeZone
    public var clock: ClockStyle

    public init(now: Date, timeZone: TimeZone = .autoupdatingCurrent, clock: ClockStyle = .current()) {
        self.now = now
        self.timeZone = timeZone
        self.clock = clock
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
}

/// How fresh the numbers are. After 30 minutes the time turns amber; after 6 hours the bars dim.
public enum Freshness: Sendable, Equatable {
    case fresh, stale, veryStale

    public static let staleAfter: TimeInterval = 30 * 60
    public static let veryStaleAfter: TimeInterval = 6 * 3600

    public static func of(updatedAt: Date, now: Date) -> Freshness {
        let age = now.timeIntervalSince(updatedAt)
        if age >= veryStaleAfter { return .veryStale }
        if age >= staleAfter { return .stale }
        return .fresh
    }
}

/// Color level of a bar: blue, amber at 75% and above, red at 90% and above.
public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical

    public static func of(percent: Double) -> UsageLevel {
        if percent >= 90 { return .critical }
        if percent >= 75 { return .warning }
        return .normal
    }
}

/// One row of the widget, ready to draw.
public struct LimitRow: Sendable, Equatable, Identifiable {
    public enum ResetState: Sendable, Equatable {
        case upcoming(Date)
        /// The reset time has passed and no fresh numbers arrived yet.
        case passed(Date)
        case unknown
    }

    public var id: String
    public var title: String
    public var usedPercent: Double
    /// Whole percent for display, e.g. 9. Nil when the reset passed (Wiggleroom doesn't guess 0%).
    public var percent: Int?
    public var percentText: String
    public var level: UsageLevel
    public var reset: ResetState
    public var resetText: String
    public var resetTextShort: String
    public var outOfRange: Bool

    public var isSession: Bool { id == LimitKind.session }
}

/// The whole card: rows plus the "As of" line.
public struct UsageDisplay: Sendable, Equatable {
    public var rows: [LimitRow]
    public var updatedAt: Date
    public var asOfText: String
    /// The same moment without "As of": "8:21 PM", "Mon 9:01 PM", "Jan 3, 9:29 PM" (0.2.3).
    public var asOfTime: String
    /// Just the day when it isn't today: "yesterday", "Mon" or "Jan 3"; nil for today (0.2.3).
    public var asOfDay: String?
    public var freshness: Freshness

    public func row(_ id: String) -> LimitRow? { rows.first { $0.id == id } }
    /// The row the small widget and the menu bar show: this week, or else the first one.
    public var primary: LimitRow? { row(LimitKind.weekly) ?? rows.first }
}

public enum UsageFormatter {
    public static func display(_ snapshot: UsageSnapshot, context: DisplayContext) -> UsageDisplay {
        let rows = snapshot.limits.map { row($0, context: context) }
        let time = asOf(snapshot.updatedAt, context: context)
        return UsageDisplay(rows: rows, updatedAt: snapshot.updatedAt,
                            asOfText: "As of " + time, asOfTime: time, asOfDay: asOfDay(snapshot.updatedAt, context: context),
                            freshness: Freshness.of(updatedAt: snapshot.updatedAt, now: context.now))
    }

    public static func title(for id: String) -> String {
        switch id {
        case LimitKind.session: return "Current session"
        case LimitKind.weekly: return "This week"
        case LimitKind.spend: return "Spend limit"
        default:
            if id.hasPrefix(LimitKind.weekly + "_") {
                let name = id.dropFirst(LimitKind.weekly.count + 1).split(separator: "_")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                return "\(name) this week"
            }
            return id
        }
    }

    /// Whole percent, rounded up like Claude's usage page, so it never shows less than was used
    /// (3.2 shows 4%). Exactly 0 stays 0%, and it never says "100%" until the limit is really
    /// used up. The tiny tolerance keeps a whole number that arrives as 3.0000000001 at 3%.
    public static func wholePercent(_ p: Double) -> Int {
        let r = Int((p - 1e-9).rounded(.up))
        return (r >= 100 && p < 100) ? 99 : max(0, r)
    }

    static func row(_ l: LimitWindow, context: DisplayContext) -> LimitRow {
        let reset: LimitRow.ResetState
        let text: String
        let short: String
        if let r = l.resetsAt {
            if r > context.now {
                reset = .upcoming(r)
                text = "Resets " + moment(r, context: context, short: false)
                short = "Resets " + moment(r, context: context, short: true)
            } else {
                reset = .passed(r)
                text = "Reset " + pastMoment(r, context: context) + ", waiting for new numbers"
                short = "Reset " + pastMoment(r, context: context)
            }
        } else {
            reset = .unknown
            text = "Reset time unknown"
            short = text
        }
        let passed: Bool = { if case .passed = reset { return true }; return false }()
        let pct = passed ? nil : wholePercent(l.usedPercent)
        return LimitRow(id: l.id, title: l.label ?? title(for: l.id), usedPercent: passed ? 0 : l.usedPercent, percent: pct,
                        percentText: pct.map { (l.outOfRange && l.usedPercent >= 100) ? "100%+ used" : "\($0)% used" } ?? "Waiting",
                        level: passed ? .normal : UsageLevel.of(percent: l.usedPercent),
                        reset: reset, resetText: text, resetTextShort: short, outOfRange: l.outOfRange)
    }

    /// "today 3:00 PM", "tomorrow 1:00 AM", "Monday 1:00 AM" (short: "Mon 1:00 AM"),
    /// "Thu, Nov 19, 8:21 PM" or "Dec 1, 1:00 AM".
    /// The weekday alone is used up to 6 days ahead, like Claude's own usage page. A reset a week
    /// away on today's weekday (right after a weekly reset it is exactly 7 days away) also shows
    /// its date, because "Thursday 8:21 PM" read on a Thursday looks like tonight (0.2.1).
    static func moment(_ date: Date, context: DisplayContext, short: Bool) -> String {
        let cal = context.calendar
        let time = format(date, pattern: timePattern(context.clock), context: context)
        let today = cal.startOfDay(for: context.now)
        let day = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "today \(time)"
        case 1: return "tomorrow \(time)"
        case -1: return "yesterday \(time)"
        case 2...6, -6 ... -2: return "\(format(date, pattern: short ? "EEE" : "EEEE", context: context)) \(time)"
        case 7: return "\(format(date, pattern: "EEE, MMM d", context: context)), \(time)"
        default: return "\(format(date, pattern: "MMM d", context: context)), \(time)"
        }
    }

    /// "2:41 PM" today, otherwise "yesterday 2:41 PM", "Mon 2:41 PM" or "Nov 2, 2:41 PM".
    static func asOf(_ date: Date, context: DisplayContext) -> String {
        if context.calendar.isDate(date, inSameDayAs: context.now) {
            return format(date, pattern: timePattern(context.clock), context: context)
        }
        return moment(date, context: context, short: true)
    }

    /// The day of an "as of" moment, or nil when it is today.
    static func asOfDay(_ date: Date, context: DisplayContext) -> String? {
        let cal = context.calendar
        if cal.isDate(date, inSameDayAs: context.now) { return nil }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: context.now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case -1: return "yesterday"
        case -6 ... -2: return format(date, pattern: "EEE", context: context)
        default: return format(date, pattern: "MMM d", context: context)
        }
    }

    /// For a reset that has passed: "at 1:00 AM" today, otherwise "Monday 1:00 AM".
    static func pastMoment(_ date: Date, context: DisplayContext) -> String {
        let cal = context.calendar
        let time = format(date, pattern: timePattern(context.clock), context: context)
        if cal.isDate(date, inSameDayAs: context.now) { return "at \(time)" }
        return moment(date, context: context, short: false)
    }

    static func timePattern(_ clock: ClockStyle) -> String { clock == .twelveHour ? "h:mm a" : "HH:mm" }

    /// English words (the app's language), with the user's time zone and clock style.
    static func format(_ date: Date, pattern: String, context: DisplayContext) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = context.timeZone
        f.calendar = context.calendar
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
