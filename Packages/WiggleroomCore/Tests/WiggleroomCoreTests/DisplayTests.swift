import Foundation
import Testing
@testable import WiggleroomCore

@Suite struct DisplayTests {
    func ctx(_ now: Date, _ tz: String, _ clock: ClockStyle = .twelveHour) -> DisplayContext {
        DisplayContext(now: now, timeZone: TimeZone(identifier: tz)!, clock: clock)
    }

    /// One reset moment (Mon Jan 18 2027, 09:00 UTC) seen from three places, in both clock styles.
    @Test(arguments: [
        (vegas, ClockStyle.twelveHour, "Resets Monday 1:00 AM", "Resets Mon 1:00 AM"),
        (vegas, ClockStyle.twentyFourHour, "Resets Monday 01:00", "Resets Mon 01:00"),
        (utc, ClockStyle.twelveHour, "Resets Monday 9:00 AM", "Resets Mon 9:00 AM"),
        (utc, ClockStyle.twentyFourHour, "Resets Monday 09:00", "Resets Mon 09:00"),
        (tokyo, ClockStyle.twelveHour, "Resets Monday 6:00 PM", "Resets Mon 6:00 PM"),
        (tokyo, ClockStyle.twentyFourHour, "Resets Monday 18:00", "Resets Mon 18:00"),
    ])
    func weeklyResetInThreeTimeZones(tz: String, clock: ClockStyle, full: String, short: String) {
        let reset = date(2027, 1, 18, 9, tz: utc)
        // "Now" is Thursday afternoon in each place, so the reset is 3 to 4 days away.
        let now = date(2027, 1, 14, 15, tz: tz)
        let s = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 9, resetsAt: reset)])
        let row = UsageFormatter.display(s, context: ctx(now, tz, clock)).rows[0]
        #expect(row.resetText == full)
        #expect(row.resetTextShort == short)
        #expect(row.percentText == "9% used")
        #expect(row.title == "This week")
    }

    @Test func todayTomorrowAroundLocalMidnight() {
        // 11:50 PM in Las Vegas is already the next day in UTC (lesson 11).
        let now = date(2027, 1, 14, 23, 50, tz: vegas)
        let soon = date(2027, 1, 14, 23, 59, tz: vegas)
        let afterMidnight = date(2027, 1, 15, 0, 30, tz: vegas)
        let c = ctx(now, vegas)
        #expect(UsageFormatter.moment(soon, context: c, short: false) == "today 11:59 PM")
        #expect(UsageFormatter.moment(afterMidnight, context: c, short: false) == "tomorrow 12:30 AM")
        // Same instants seen from Tokyo, where it's already the afternoon of the 15th.
        let t = ctx(now, tokyo, .twentyFourHour)
        #expect(UsageFormatter.moment(afterMidnight, context: t, short: false) == "today 17:30")
    }

    @Test func daylightSavingChangeKeepsTheRightLocalTime() {
        // US clocks jump forward on Sunday Mar 14, 2027 at 2:00 AM.
        let now = date(2027, 3, 12, 12, tz: vegas)
        let reset = date(2027, 3, 15, 1, tz: vegas)   // Monday 1:00 AM, after the change
        let s = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 50, resetsAt: reset)])
        #expect(UsageFormatter.display(s, context: ctx(now, vegas)).rows[0].resetText == "Resets Monday 1:00 AM")
        // And a reset in the skipped-over night: Sunday 3:30 AM is 2 days ahead.
        let odd = date(2027, 3, 14, 3, 30, tz: vegas)
        #expect(UsageFormatter.moment(odd, context: ctx(now, vegas), short: true) == "Sun 3:30 AM")
        // Fall back (Nov 7, 2027): the 1:30 AM that happens twice still reads 1:30 AM.
        let fallNow = date(2027, 11, 6, 20, tz: vegas)
        let firstOneThirty = Date(timeIntervalSince1970: date(2027, 11, 7, 0, tz: vegas).timeIntervalSince1970 + 5400)
        #expect(UsageFormatter.moment(firstOneThirty, context: ctx(fallNow, vegas), short: false) == "tomorrow 1:30 AM")
    }

    @Test func farResetsShowTheDate() {
        let now = date(2027, 1, 14, 12, tz: utc)
        #expect(UsageFormatter.moment(date(2027, 2, 1, 0, tz: utc), context: ctx(now, utc), short: false) == "Feb 1, 12:00 AM")
    }

    @Test func asOfTextAndFreshness() {
        let updated = date(2027, 1, 14, 14, 41, tz: vegas)
        let s = UsageSnapshot(updatedAt: updated, limits: [LimitWindow(id: "seven_day", usedPercent: 9, resetsAt: updated.addingTimeInterval(86400 * 3))])
        let d0 = UsageFormatter.display(s, context: ctx(updated.addingTimeInterval(60), vegas))
        #expect(d0.asOfText == "As of 2:41 PM")
        #expect(d0.freshness == .fresh)
        #expect(UsageFormatter.display(s, context: ctx(updated.addingTimeInterval(29 * 60), vegas)).freshness == .fresh)
        #expect(UsageFormatter.display(s, context: ctx(updated.addingTimeInterval(30 * 60), vegas)).freshness == .stale)
        #expect(UsageFormatter.display(s, context: ctx(updated.addingTimeInterval(6 * 3600), vegas)).freshness == .veryStale)
        let nextDay = UsageFormatter.display(s, context: ctx(updated.addingTimeInterval(12 * 3600), vegas))
        #expect(nextDay.asOfText == "As of yesterday 2:41 PM")
        #expect(UsageFormatter.display(s, context: ctx(updated.addingTimeInterval(60), vegas, .twentyFourHour)).asOfText == "As of 14:41")
    }

    @Test func resetPassedSaysWaitingInsteadOfGuessing() {
        let reset = date(2027, 1, 14, 1, tz: vegas)
        let now = date(2027, 1, 14, 3, tz: vegas)
        let s = UsageSnapshot(updatedAt: reset.addingTimeInterval(-600),
                              limits: [LimitWindow(id: "five_hour", usedPercent: 88, resetsAt: reset)])
        let row = UsageFormatter.display(s, context: ctx(now, vegas)).rows[0]
        #expect(row.resetText == "Reset at 1:00 AM, waiting for new numbers")
        #expect(row.percent == nil)
        #expect(row.percentText == "Waiting")
        #expect(row.usedPercent == 0)
        #expect(row.level == .normal)
        // A reset from an earlier day names the day.
        let later = UsageFormatter.display(s, context: ctx(now.addingTimeInterval(86400 * 2), vegas)).rows[0]
        #expect(later.resetText == "Reset Thursday 1:00 AM, waiting for new numbers")
    }

    @Test func levelsAndRounding() {
        #expect(UsageLevel.of(percent: 74.9) == .normal)
        #expect(UsageLevel.of(percent: 75) == .warning)
        #expect(UsageLevel.of(percent: 89.99) == .warning)
        #expect(UsageLevel.of(percent: 90) == .critical)
        #expect(UsageFormatter.wholePercent(9.4) == 9)
        #expect(UsageFormatter.wholePercent(9.5) == 10)
        #expect(UsageFormatter.wholePercent(99.7) == 99)
        #expect(UsageFormatter.wholePercent(100) == 100)
        #expect(UsageFormatter.wholePercent(0) == 0)
    }

    @Test func titles() {
        #expect(UsageFormatter.title(for: "five_hour") == "Current session")
        #expect(UsageFormatter.title(for: "seven_day") == "This week")
        #expect(UsageFormatter.title(for: "seven_day_opus") == "Opus this week")
        #expect(UsageFormatter.title(for: "seven_day_claude_code") == "Claude Code this week")
        #expect(UsageFormatter.title(for: "spend_limit") == "Spend limit")
    }

    @Test func primaryRowIsWeekly() {
        let now = Date(timeIntervalSince1970: 1_799_990_000)
        let s = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "five_hour", usedPercent: 5, resetsAt: nil),
                                                         LimitWindow(id: "seven_day", usedPercent: 6, resetsAt: nil)])
        #expect(UsageFormatter.display(s, context: ctx(now, utc)).primary?.id == "seven_day")
        #expect(UsageFormatter.display(s, context: ctx(now, utc)).row("five_hour")?.resetText == "Reset time unknown")
    }

    @Test func clockStyleFromLocale() {
        #expect(ClockStyle.current(locale: Locale(identifier: "en_US")) == .twelveHour)
        #expect(ClockStyle.current(locale: Locale(identifier: "en_GB")) == .twentyFourHour)
        #expect(ClockStyle.current(locale: Locale(identifier: "de_DE")) == .twentyFourHour)
        #expect(ClockStyle.current(locale: Locale(identifier: "ja_JP")) == .twentyFourHour)
    }
}
