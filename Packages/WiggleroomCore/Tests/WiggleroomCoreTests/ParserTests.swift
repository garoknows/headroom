import Foundation
import Testing
@testable import WiggleroomCore

@Suite struct ParserTests {
    let now = Date(timeIntervalSince1970: 1_799_990_000)

    @Test func fullPayloadKeepsOnlyTheLimits() throws {
        let s = try #require(RateLimitParser.snapshot(fromStatusLine: Fixture.data("full-payload.json"), now: now))
        #expect(s.limits.map(\.id) == ["five_hour", "seven_day", "spend_limit"])
        #expect(s.limit("five_hour")?.usedPercent == 23.5)
        #expect(s.limit("five_hour")?.resetsAt == Date(timeIntervalSince1970: 1_799_996_400))
        #expect(s.limit("seven_day")?.usedPercent == 41.2)
        #expect(s.limit("spend_limit")?.usedPercent == 62.8)
        #expect(s.updatedAt == now)
    }

    @Test func secondsMillisecondsAndISOAllGiveTheSameMoment() throws {
        let ms = try #require(RateLimitParser.snapshot(fromStatusLine: Fixture.data("ms-resets.json"), now: now))
        #expect(ms.limit("seven_day")?.resetsAt == Date(timeIntervalSince1970: 1_800_417_600))
        let iso = try #require(RateLimitParser.snapshot(fromStatusLine: Fixture.data("iso-resets.json"), now: now))
        #expect(iso.limit("five_hour")?.resetsAt == date(2027, 1, 15, 15, tz: utc))
        #expect(iso.limit("five_hour")?.usedPercent == 12.5) // numeric string accepted
        let weekly = try #require(iso.limit("seven_day")?.resetsAt)
        #expect(abs(weekly.timeIntervalSince(date(2027, 1, 18, 9, tz: utc)) - 0.25) < 0.001)
        #expect(RateLimitParser.date("1800417600") == Date(timeIntervalSince1970: 1_800_417_600))
    }

    @Test func missingRateLimitsGivesNothing() {
        #expect(RateLimitParser.snapshot(fromStatusLine: Fixture.data("no-rate-limits.json"), now: now) == nil)
        #expect(RateLimitParser.snapshot(fromStatusLine: Data("{}".utf8), now: now) == nil)
        #expect(RateLimitParser.snapshot(fromStatusLine: Data("{\"rate_limits\":{}}".utf8), now: now) == nil)
        #expect(RateLimitParser.snapshot(fromStatusLine: Data("{\"rate_limits\":null}".utf8), now: now) == nil)
    }

    @Test func brokenInputNeverCrashes() {
        for text in ["", "not json", "[1,2,3]", "\"text\"", "{\"rate_limits\":[1]}", "{\"rate_limits\":", "\u{0}\u{1}"] {
            #expect(RateLimitParser.snapshot(fromStatusLine: Data(text.utf8), now: now) == nil)
        }
        var random = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let bytes = (0..<Int.random(in: 0...64, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) }
            _ = RateLimitParser.snapshot(fromStatusLine: Data(bytes), now: now)
        }
    }

    @Test func weeklyOnlyPlanHasNoSessionRow() throws {
        let s = try #require(RateLimitParser.snapshot(fromStatusLine: Fixture.data("weekly-only.json"), now: now))
        #expect(s.limits.map(\.id) == ["seven_day"])
    }

    @Test func oddValuesAreClampedFlaggedOrIgnored() throws {
        let s = try #require(RateLimitParser.snapshot(fromStatusLine: Fixture.data("odd-values.json"), now: now))
        // Unknown names, malformed names, booleans and non-objects are ignored.
        #expect(s.limits.map(\.id) == ["five_hour", "seven_day", "seven_day_opus"])
        let five = try #require(s.limit("five_hour"))
        #expect(five.usedPercent == 100 && five.outOfRange)
        let week = try #require(s.limit("seven_day"))
        #expect(week.usedPercent == 0 && week.outOfRange)
        #expect(week.resetsAt == nil) // "not a date" is unknown, not a guess
        #expect(s.limit("seven_day_opus")?.outOfRange == false)
    }

    @Test func implausibleDatesAreUnknown() {
        #expect(RateLimitParser.date(0) == nil)
        #expect(RateLimitParser.date(-5) == nil)
        #expect(RateLimitParser.date(Double.infinity) == nil)
        #expect(RateLimitParser.date(true) == nil)
        #expect(RateLimitParser.date(5_000_000_000) == nil) // year 2128
        #expect(RateLimitParser.date("2027-13-45T99:00:00Z") == nil)
    }

    @Test func limitNames() {
        #expect(LimitKind.isSupported("five_hour"))
        #expect(LimitKind.isSupported("seven_day_opus"))
        #expect(!LimitKind.isSupported("seven_day_"))
        #expect(!LimitKind.isSupported("seven_days"))
        #expect(!LimitKind.isSupported("Seven_day"))
        #expect(!LimitKind.isSupported("seven_day_" + String(repeating: "x", count: 40)))
    }
}
