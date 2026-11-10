import Foundation
import Testing
@testable import WiggleroomCore

@Suite struct AlertTests {
    let now = Date(timeIntervalSince1970: 1_799_990_000)
    func snap(_ p: Double, reset: TimeInterval = 3 * 86400, age: TimeInterval = 0, id: String = "seven_day") -> UsageSnapshot {
        UsageSnapshot(updatedAt: now.addingTimeInterval(-age),
                      limits: [LimitWindow(id: id, usedPercent: p, resetsAt: now.addingTimeInterval(reset))])
    }
    func claude(_ s: UsageSnapshot) -> [ToolSnapshot] { [ToolSnapshot(tool: .claudeCode, usage: s)] }
    func evaluate(_ tools: [ToolSnapshot], _ settings: AlertSettings = .default, _ record: AlertRecord = AlertRecord()) -> (alerts: [UsageAlert], record: AlertRecord) {
        AlertPlanner.evaluate(tools: tools, settings: settings, record: record, now: now)
    }

    @Test func firesOncePerWindowAtNinetyByDefault() throws {
        var r = evaluate(claude(snap(89)))
        #expect(r.alerts.isEmpty)
        r = evaluate(claude(snap(91)), .default, r.record)
        let alert = try #require(r.alerts.first)
        #expect(r.alerts.count == 1)
        #expect(alert.threshold == 90 && alert.percent == 91 && alert.tool == .claudeCode)
        #expect(alert.title == "Claude Code: 91% of your weekly limit used.")
        // Same week, more usage: no repeat.
        let again = evaluate(claude(snap(95)), .default, r.record)
        #expect(again.alerts.isEmpty)
        // Reset time moved by a few seconds: still the same week.
        #expect(evaluate(claude(snap(96, reset: 3 * 86400 + 30)), .default, again.record).alerts.isEmpty)
        // Next week: fires again.
        #expect(evaluate(claude(snap(92, reset: 10 * 86400)), .default, again.record).alerts.first?.threshold == 90)
    }

    /// The PRD's example text, in three time zones and both clocks (lesson 11).
    @Test(arguments: [
        (vegas, ClockStyle.twelveHour, "Resets Monday 1:00 AM."), (utc, .twentyFourHour, "Resets Monday 09:00."),
        (tokyo, .twelveHour, "Resets Monday 6:00 PM."),
    ])
    func codexAlertText(tz: String, clock: ClockStyle, body: String) throws {
        let reset = date(2027, 1, 18, 9, tz: utc)
        let at = date(2027, 1, 14, 15, tz: tz)
        let s = UsageSnapshot(updatedAt: at, limits: [LimitWindow(id: "seven_day", usedPercent: 90, resetsAt: reset, label: "This week", windowMinutes: 10080)])
        let a = try #require(AlertPlanner.evaluate(tools: [ToolSnapshot(tool: .codex, usage: s)], settings: .default, record: AlertRecord(), now: at).alerts.first)
        #expect(a.title == "Codex: 90% of your weekly limit used.")
        #expect(a.body(context: DisplayContext(now: at, timeZone: TimeZone(identifier: tz)!, clock: clock)) == body)
    }

    /// Thresholds apply per tool and per window, at most one alert per level each.
    @Test func everyToolAndEveryWindowOnItsOwn() {
        let claudeBoth = UsageSnapshot(updatedAt: now, limits: [
            LimitWindow(id: "five_hour", usedPercent: 95, resetsAt: now.addingTimeInterval(3600)),
            LimitWindow(id: "seven_day", usedPercent: 91, resetsAt: now.addingTimeInterval(3 * 86400)),
        ])
        let codex = UsageSnapshot(updatedAt: now, limits: [
            LimitWindow(id: "five_hour", usedPercent: 40, resetsAt: now.addingTimeInterval(3600), label: "5-hour", windowMinutes: 300),
            LimitWindow(id: "seven_day", usedPercent: 93, resetsAt: now.addingTimeInterval(3 * 86400), label: "This week", windowMinutes: 10080),
        ])
        let tools = [ToolSnapshot(tool: .claudeCode, usage: claudeBoth), ToolSnapshot(tool: .codex, usage: codex)]
        let r = evaluate(tools)
        #expect(Set(r.alerts.map(\.title)) == [
            "Claude Code: 95% of your 5-hour limit used.", "Claude Code: 91% of your weekly limit used.", "Codex: 93% of your weekly limit used.",
        ])
        #expect(Set(r.alerts.map(\.identifier)).count == 3)
        #expect(evaluate(tools, .default, r.record).alerts.isEmpty)   // never twice
        // Codex's 5-hour window passing 90 later is a new alert; nothing else repeats.
        var later = codex; later.limits[0].usedPercent = 90
        let next = evaluate([ToolSnapshot(tool: .claudeCode, usage: claudeBoth), ToolSnapshot(tool: .codex, usage: later)], .default, r.record)
        #expect(next.alerts.map(\.title) == ["Codex: 90% of your 5-hour limit used."])
    }

    @Test func bothThresholdsCrossedAtOnceGiveOneAlert() {
        let s = AlertSettings(enabled: true, thresholds: [90, 75])
        let r = evaluate(claude(snap(93)), s)
        #expect(r.alerts.map(\.threshold) == [90])
        #expect(Set(r.record.fired.keys) == [AlertRecord.key(.claudeCode, "seven_day", 75), AlertRecord.key(.claudeCode, "seven_day", 90)])
        #expect(evaluate(claude(snap(94)), s, r.record).alerts.isEmpty)
    }

    @Test func seventyFiveThenNinety() {
        let s = AlertSettings(enabled: true, thresholds: [75, 90])
        let a = evaluate(claude(snap(76)), s)
        #expect(a.alerts.map(\.threshold) == [75])
        #expect(evaluate(claude(snap(90)), s, a.record).alerts.map(\.threshold) == [90])
    }

    @Test func offSwitchAndSafePaths() {
        let off = AlertSettings(enabled: false, thresholds: [90])
        #expect(evaluate(claude(snap(99)), off).alerts.isEmpty)
        // Old numbers, a passed reset, or no data never alert (lesson 7: unknown means do nothing).
        #expect(evaluate(claude(snap(99, age: 7 * 3600))).alerts.isEmpty)
        #expect(evaluate(claude(snap(99, reset: -60))).alerts.isEmpty)
        #expect(evaluate([]).alerts.isEmpty)
        let noReset = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 99, resetsAt: nil)])
        #expect(evaluate(claude(noReset)).alerts.isEmpty)
    }

    /// After the upgrade, an alert 0.1 already sent this week isn't sent again.
    @Test func oneDotOneRecordIsRespected() {
        let old = AlertRecord(fired: ["90": now.addingTimeInterval(3 * 86400)])
        #expect(evaluate(claude(snap(95)), .default, old).alerts.isEmpty)
    }

    @Test func oldRecordsAreForgotten() {
        let rec = AlertRecord(fired: [AlertRecord.key(.codex, "seven_day", 90): now.addingTimeInterval(-2 * 86400), "90": now.addingTimeInterval(-2 * 86400)])
        #expect(evaluate([], .default, rec).record.fired.isEmpty)
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
