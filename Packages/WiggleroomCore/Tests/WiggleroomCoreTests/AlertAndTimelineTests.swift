import Foundation
import Testing
@testable import WiggleroomCore

@Suite struct AlertTests {
    let now = Date(timeIntervalSince1970: 1_799_990_000)
    func snap(_ p: Double, reset: TimeInterval = 3 * 86400, age: TimeInterval = 0) -> UsageSnapshot {
        UsageSnapshot(updatedAt: now.addingTimeInterval(-age),
                      limits: [LimitWindow(id: "seven_day", usedPercent: p, resetsAt: now.addingTimeInterval(reset))])
    }

    @Test func firesOncePerWeekAtNinetyByDefault() throws {
        var record = AlertRecord()
        var r = AlertPlanner.evaluate(snapshot: snap(89), settings: .default, record: record, now: now)
        #expect(r.alert == nil)
        record = r.record
        r = AlertPlanner.evaluate(snapshot: snap(91), settings: .default, record: record, now: now)
        let alert = try #require(r.alert)
        #expect(alert.threshold == 90 && alert.percent == 91)
        #expect(alert.title == "You've used 91% of this week's Claude limit")
        record = r.record
        // Same week, more usage: no repeat.
        r = AlertPlanner.evaluate(snapshot: snap(95), settings: .default, record: record, now: now)
        #expect(r.alert == nil)
        // Reset time moved by a few seconds (Claude Code rounding): still the same week.
        let jitter = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 96, resetsAt: now.addingTimeInterval(3 * 86400 + 30))])
        #expect(AlertPlanner.evaluate(snapshot: jitter, settings: .default, record: r.record, now: now).alert == nil)
        // Next week: fires again.
        let nextWeek = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 92, resetsAt: now.addingTimeInterval(10 * 86400))])
        #expect(AlertPlanner.evaluate(snapshot: nextWeek, settings: .default, record: r.record, now: now).alert?.threshold == 90)
    }

    @Test func bothThresholdsCrossedAtOnceGiveOneAlert() {
        let s = AlertSettings(enabled: true, thresholds: [90, 75])
        let r = AlertPlanner.evaluate(snapshot: snap(93), settings: s, record: AlertRecord(), now: now)
        #expect(r.alert?.threshold == 90)
        #expect(Set(r.record.fired.keys) == ["75", "90"])
        #expect(AlertPlanner.evaluate(snapshot: snap(94), settings: s, record: r.record, now: now).alert == nil)
    }

    @Test func seventyFiveThenNinety() {
        let s = AlertSettings(enabled: true, thresholds: [75, 90])
        let a = AlertPlanner.evaluate(snapshot: snap(76), settings: s, record: AlertRecord(), now: now)
        #expect(a.alert?.threshold == 75)
        let b = AlertPlanner.evaluate(snapshot: snap(90), settings: s, record: a.record, now: now)
        #expect(b.alert?.threshold == 90)
    }

    @Test func offSwitchAndSafePaths() {
        let off = AlertSettings(enabled: false, thresholds: [90])
        #expect(AlertPlanner.evaluate(snapshot: snap(99), settings: off, record: AlertRecord(), now: now).alert == nil)
        // Old numbers, a passed reset, or no data never alert (lesson 7: unknown means do nothing).
        #expect(AlertPlanner.evaluate(snapshot: snap(99, age: 7 * 3600), settings: .default, record: AlertRecord(), now: now).alert == nil)
        #expect(AlertPlanner.evaluate(snapshot: snap(99, reset: -60), settings: .default, record: AlertRecord(), now: now).alert == nil)
        #expect(AlertPlanner.evaluate(snapshot: nil, settings: .default, record: AlertRecord(), now: now).alert == nil)
        let sessionOnly = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "five_hour", usedPercent: 99, resetsAt: now.addingTimeInterval(60))])
        #expect(AlertPlanner.evaluate(snapshot: sessionOnly, settings: .default, record: AlertRecord(), now: now).alert == nil)
    }

    @Test func oldRecordsAreForgotten() {
        let rec = AlertRecord(fired: ["90": now.addingTimeInterval(-2 * 86400)])
        #expect(AlertPlanner.evaluate(snapshot: nil, settings: .default, record: rec, now: now).record.fired.isEmpty)
    }

    @Test func settingsAreCleaned() {
        #expect(AlertSettings(enabled: true, thresholds: [90, 0, 150, 75]).thresholds == [75, 90])
    }
}

@Suite struct TimelineTests {
    @Test func entriesCoverStalenessResetsAndMidnight() {
        let tz = TimeZone(identifier: vegas)!
        let now = date(2027, 1, 14, 22, 10, tz: vegas)
        let reset = now.addingTimeInterval(3 * 3600 + 7)
        let s = UsageSnapshot(updatedAt: now.addingTimeInterval(-5 * 60),
                              limits: [LimitWindow(id: "five_hour", usedPercent: 10, resetsAt: reset)])
        let d = TimelinePlan.dates(for: s, now: now, timeZone: tz)
        #expect(d.first == now)
        #expect(d == d.sorted() && Set(d).count == d.count)
        #expect(d.contains(reset.addingTimeInterval(1)))
        #expect(d.contains(now.addingTimeInterval(25 * 60)))            // turns stale at 30 min old
        #expect(d.contains(now.addingTimeInterval(6 * 3600 - 5 * 60)))  // dims at 6 hours old
        #expect(d.contains(date(2027, 1, 15, 0, tz: vegas)))             // "today" changes at midnight
        #expect(d.contains(now.addingTimeInterval(15 * 60)))
        #expect(d.last! <= now.addingTimeInterval(TimelinePlan.horizon))
    }

    /// Lesson 11: nothing may sit on screen for days. Entries stop at the horizon, and WidgetKit
    /// asks for a new timeline then, so "today", "tomorrow" and "as of" are recomputed.
    @Test func farResetsDoNotStretchTheTimeline() {
        let now = date(2027, 1, 14, 22, 10, tz: vegas)
        let s = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 10, resetsAt: now.addingTimeInterval(5 * 86400))])
        let d = TimelinePlan.dates(for: s, now: now, timeZone: TimeZone(identifier: vegas)!)
        #expect(d.last! <= now.addingTimeInterval(TimelinePlan.horizon))
    }

    @Test func emptyStateStillRefreshes() {
        let now = Date(timeIntervalSince1970: 1_799_990_000)
        #expect(TimelinePlan.dates(for: nil, now: now).count > 10)
    }
}
