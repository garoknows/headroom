import Foundation
import Testing
@testable import WiggleroomCore

/// 0.2.2: a tool that hasn't been used lately must not make the whole popover look stale, and no
/// "As of" line may show numbers as fresher than they are (DECISIONS D180).
@Suite struct AsOfPlanTests {
    let now = date(2027, 1, 14, 21, 31, tz: vegas)
    var ctx: DisplayContext { DisplayContext(now: now, timeZone: TimeZone(identifier: vegas)!, clock: .twelveHour) }

    func tool(_ t: Tool, minutesOld: Double) -> ToolDisplay {
        let at = now.addingTimeInterval(-minutesOld * 60)
        let s = UsageSnapshot(updatedAt: at, limits: [LimitWindow(id: "seven_day", usedPercent: 30, resetsAt: now.addingTimeInterval(4 * 86400))])
        return ToolDisplay(tool: t, display: UsageFormatter.display(s, context: ctx))
    }

    @Test func anOldToolGetsItsOwnLineAndTheSharedLineStaysFresh() {
        // Claude Code from 2 minutes ago, Codex from 70 minutes ago.
        let claude = tool(.claudeCode, minutesOld: 2), codex = tool(.codex, minutesOld: 70)
        let plan = ToolDisplay.asOfPlan([claude, codex])
        #expect(plan.separate == [.codex])
        #expect(plan.shared?.updatedAt == claude.display.updatedAt)
        #expect(plan.shared?.freshness == .fresh)
    }

    @Test func theSharedLineIsNeverFresherThanTheToolsItCovers() {
        // Both fresh, 19 minutes apart: one line, with the older time.
        let claude = tool(.claudeCode, minutesOld: 2), codex = tool(.codex, minutesOld: 21)
        let plan = ToolDisplay.asOfPlan([claude, codex])
        #expect(plan.separate.isEmpty)
        #expect(plan.shared?.updatedAt == codex.display.updatedAt)
    }

    @Test func bothOldIsOneAmberLine() {
        let claude = tool(.claudeCode, minutesOld: 120), codex = tool(.codex, minutesOld: 180)
        let plan = ToolDisplay.asOfPlan([claude, codex])
        #expect(plan.separate.isEmpty)
        #expect(plan.shared?.updatedAt == codex.display.updatedAt)
        #expect(plan.shared?.freshness == .stale)
    }

    @Test func aVeryStaleToolIsSeparateFromAStaleOne() {
        let claude = tool(.claudeCode, minutesOld: 45), codex = tool(.codex, minutesOld: 7 * 60)
        let plan = ToolDisplay.asOfPlan([codex, claude])
        #expect(plan.separate == [.codex])
        #expect(plan.shared?.updatedAt == claude.display.updatedAt)
        #expect(plan.shared?.freshness == .stale)
    }

    @Test func oneToolOrNone() {
        let claude = tool(.claudeCode, minutesOld: 50)
        #expect(ToolDisplay.asOfPlan([claude]) == AsOfPlan(shared: claude.display, separate: []))
        #expect(ToolDisplay.asOfPlan([]) == AsOfPlan(shared: nil, separate: []))
    }
}
