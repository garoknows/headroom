import Foundation
import Testing
@testable import HeadroomCore

@Suite struct PolicyTests {
    let now = Date(timeIntervalSince1970: 1_799_990_000)
    func snap(_ t: TimeInterval, _ limits: [LimitWindow]) -> UsageSnapshot {
        UsageSnapshot(updatedAt: now.addingTimeInterval(t), limits: limits)
    }
    func lim(_ id: String, _ p: Double, reset: TimeInterval?) -> LimitWindow {
        LimitWindow(id: id, usedPercent: p, resetsAt: reset.map { now.addingTimeInterval($0) })
    }

    @Test func newestUpdateWins() {
        let older = snap(-10, [lim("seven_day", 10, reset: 3600)])
        let newer = snap(0, [lim("seven_day", 12, reset: 3600)])
        #expect(SnapshotPolicy.merge(existing: older, incoming: newer, now: now) == newer)
        // A slower session finishing late with older numbers doesn't overwrite newer ones.
        #expect(SnapshotPolicy.merge(existing: newer, incoming: older, now: now) == newer)
    }

    @Test func laterResetWinsForOneLimit() {
        let current = snap(-10, [lim("five_hour", 5, reset: 4 * 3600)])
        let staleWindow = snap(0, [lim("five_hour", 95, reset: -3600)])
        let m = SnapshotPolicy.merge(existing: current, incoming: staleWindow, now: now)
        #expect(m.limit("five_hour")?.usedPercent == 5)
        #expect(m.updatedAt == now)
    }

    @Test func withinOneWindowUsageNeverGoesDown() {
        // An idle session redraws its status line with older numbers for the same week.
        let fresh = snap(-30, [lim("seven_day", 62, reset: 86400)])
        let idle = snap(0, [lim("seven_day", 55, reset: 86400 + 20)])
        #expect(SnapshotPolicy.merge(existing: fresh, incoming: idle, now: now).limit("seven_day")?.usedPercent == 62)
    }

    @Test func aResetMovedEarlierIsAccepted() {
        // The week now resets on Friday instead of Monday: fresh numbers for the new window win.
        let old = snap(-60, [lim("seven_day", 80, reset: 4 * 86400)])
        let moved = snap(0, [lim("seven_day", 3, reset: 86400)])
        #expect(SnapshotPolicy.merge(existing: old, incoming: moved, now: now).limit("seven_day")?.usedPercent == 3)
    }

    @Test func passedWindowIsKeptUntilNewNumbersArrive() {
        let existing = snap(-7200, [lim("five_hour", 80, reset: -60), lim("seven_day", 30, reset: 86400)])
        let incoming = snap(0, [lim("seven_day", 31, reset: 86400)])
        let m = SnapshotPolicy.merge(existing: existing, incoming: incoming, now: now)
        #expect(m.limits.map(\.id) == ["five_hour", "seven_day"])
        // ...but a missing window whose reset is still ahead is dropped (the plan changed).
        let e2 = snap(-60, [lim("five_hour", 80, reset: 3600), lim("seven_day", 30, reset: 86400)])
        #expect(SnapshotPolicy.merge(existing: e2, incoming: incoming, now: now).limits.map(\.id) == ["seven_day"])
        // ...and one that reset more than a week ago is dropped too.
        let e3 = snap(-60, [lim("five_hour", 80, reset: -8 * 86400), lim("seven_day", 30, reset: 86400)])
        #expect(SnapshotPolicy.merge(existing: e3, incoming: incoming, now: now).limits.map(\.id) == ["seven_day"])
    }

    @Test func plausibility() {
        #expect(SnapshotPolicy.isPlausible(snap(0, [lim("seven_day", 50, reset: 100)]), now: now))
        #expect(!SnapshotPolicy.isPlausible(snap(0, []), now: now))
        #expect(!SnapshotPolicy.isPlausible(snap(0, [lim("seven_day", 150, reset: 100)]), now: now))
        #expect(!SnapshotPolicy.isPlausible(snap(0, [lim("seven_day", .nan, reset: 100)]), now: now))
        #expect(!SnapshotPolicy.isPlausible(snap(0, [lim("mystery", 5, reset: 100)]), now: now))
        #expect(!SnapshotPolicy.isPlausible(snap(0, [lim("seven_day", 5, reset: 100), lim("seven_day", 6, reset: 100)]), now: now))
        #expect(!SnapshotPolicy.isPlausible(snap(3600, [lim("seven_day", 5, reset: 100)]), now: now)) // from the future
        var wrongFormat = snap(0, [lim("seven_day", 5, reset: 100)]); wrongFormat.format = 2
        #expect(!SnapshotPolicy.isPlausible(wrongFormat, now: now))
    }

    @Test func goodDataIsNeverReplacedByBadOrOlderData() {
        let good = snap(-60, [lim("seven_day", 40, reset: 3600)])
        let newer = snap(0, [lim("seven_day", 41, reset: 3600)])
        let bad = snap(0, [lim("seven_day", 400, reset: 3600)])
        #expect(SnapshotPolicy.shouldReplace(current: nil, with: good, now: now))
        #expect(SnapshotPolicy.shouldReplace(current: good, with: newer, now: now))
        #expect(!SnapshotPolicy.shouldReplace(current: good, with: nil, now: now))
        #expect(!SnapshotPolicy.shouldReplace(current: good, with: bad, now: now))
        #expect(!SnapshotPolicy.shouldReplace(current: newer, with: good, now: now))
        #expect(!SnapshotPolicy.shouldReplace(current: good, with: good, now: now))
        // A broken current snapshot can be replaced by any good one.
        #expect(SnapshotPolicy.shouldReplace(current: bad, with: good, now: now))
    }

    @Test func encodingRoundTripsAndUsesOnlyAllowedKeys() throws {
        let s = snap(0, [lim("seven_day", 40, reset: 3600), LimitWindow(id: "five_hour", usedPercent: 3, outOfRange: true, resetsAt: nil)])
        let data = try s.encoded()
        #expect(UsageSnapshot.decode(data) == s)
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(top.keys) == UsageSnapshot.allowedKeys)
    }
}
