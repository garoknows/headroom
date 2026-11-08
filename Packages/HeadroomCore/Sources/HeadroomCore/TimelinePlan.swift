import Foundation

/// When the widget should redraw on its own (WidgetKit asks for a list of moments in advance).
public enum TimelinePlan {
    public static let step: TimeInterval = 15 * 60
    public static let horizon: TimeInterval = Freshness.veryStaleAfter + step

    /// Now; every 15 minutes up to just past the 6-hour "very stale" point; one second after each
    /// reset (so the row switches to "Reset at…"); and each local midnight in that span (so
    /// "today" and "tomorrow" stay right). Sorted, no duplicates.
    public static func dates(for snapshot: UsageSnapshot?, now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> [Date] {
        var out: [Date] = [now]
        var t = now.addingTimeInterval(step)
        let end = now.addingTimeInterval(horizon)
        while t <= end { out.append(t); t.addTimeInterval(step) }
        if let snapshot {
            for l in snapshot.limits {
                if let r = l.resetsAt, r > now { out.append(r.addingTimeInterval(1)) }
            }
            // The freshness changes exactly at 30 minutes and 6 hours after the update.
            for age in [Freshness.staleAfter, Freshness.veryStaleAfter] {
                let d = snapshot.updatedAt.addingTimeInterval(age)
                if d > now { out.append(d) }
            }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var day = cal.startOfDay(for: now)
        for _ in 0..<2 {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = cal.startOfDay(for: next)
            if day > now && day <= end { out.append(day) }
        }
        return Array(Set(out)).sorted()
    }
}
