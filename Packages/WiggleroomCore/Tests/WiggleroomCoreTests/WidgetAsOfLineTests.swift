import Foundation
import Testing
@testable import WiggleroomCore

/// 0.2.3: the medium widget's All tools line uses the popover's rule (D180) on one line:
/// "As of 9:29 PM · Codex 8:21 PM" (D186, D187), with shorter versions for long dates.
@Suite struct WidgetAsOfLineTests {
    let now = date(2027, 1, 14, 21, 31, tz: vegas)   // Thursday
    var ctx: DisplayContext { DisplayContext(now: now, timeZone: TimeZone(identifier: vegas)!, clock: .twelveHour) }

    func tool(_ t: Tool, minutesOld: Double) -> ToolDisplay {
        let s = UsageSnapshot(updatedAt: now.addingTimeInterval(-minutesOld * 60),
                              limits: [LimitWindow(id: "seven_day", usedPercent: 30, resetsAt: now.addingTimeInterval(4 * 86400))])
        return ToolDisplay(tool: t, display: UsageFormatter.display(s, context: ctx))
    }

    @Test func anOldToolGetsItsNameAndTimeAfterTheSharedTime() {
        let claude = tool(.claudeCode, minutesOld: 2), codex = tool(.codex, minutesOld: 70)
        let line = WidgetAsOfLine.make([claude, codex])
        #expect(line.shared?.updatedAt == claude.display.updatedAt)
        #expect(line.shared?.freshness == .fresh)
        #expect(line.shared?.asOfText == "As of 9:29 PM")
        #expect(line.older == [WidgetAsOfLine.Older(tool: .codex, time: "8:21 PM", day: nil)])
        #expect(line.olderTexts(level: 0) == ["Codex 8:21 PM"])
        // Today's time is the only thing to say, so the middle version keeps it.
        #expect(line.olderTexts(level: 1) == ["Codex 8:21 PM"])
        #expect(line.olderTexts(level: 2) == ["Codex"])
    }

    @Test func olderDaysGetShorterVersions() {
        let claude = tool(.claudeCode, minutesOld: 2)
        let threeDays = WidgetAsOfLine.make([claude, tool(.codex, minutesOld: 3 * 1440 + 30)])
        #expect(threeDays.olderTexts(level: 0) == ["Codex Mon 9:01 PM"])
        #expect(threeDays.olderTexts(level: 1) == ["Codex Mon"])
        #expect(threeDays.olderTexts(level: 2) == ["Codex"])
        let yesterday = WidgetAsOfLine.make([claude, tool(.codex, minutesOld: 1440)])
        #expect(yesterday.olderTexts(level: 0) == ["Codex yesterday 9:31 PM"])
        #expect(yesterday.olderTexts(level: 1) == ["Codex yesterday"])
        let eightDays = WidgetAsOfLine.make([claude, tool(.codex, minutesOld: 8 * 1440)])
        #expect(eightDays.olderTexts(level: 0) == ["Codex Jan 6, 9:31 PM"])
        #expect(eightDays.olderTexts(level: 1) == ["Codex Jan 6"])
        #expect(eightDays.olderTexts(level: 2) == ["Codex"])
    }

    @Test func toolsAtTheSameLevelShareOneHonestTime() {
        // Both fresh, 19 minutes apart: the older time, nothing extra.
        let fresh = WidgetAsOfLine.make([tool(.claudeCode, minutesOld: 2), tool(.codex, minutesOld: 21)])
        #expect(fresh.older.isEmpty)
        #expect(fresh.shared?.asOfText == "As of 9:10 PM")
        // Both stale: one amber line with the older time.
        let stale = WidgetAsOfLine.make([tool(.claudeCode, minutesOld: 120), tool(.codex, minutesOld: 180)])
        #expect(stale.older.isEmpty)
        #expect(stale.shared?.freshness == .stale)
        #expect(stale.shared?.asOfText == "As of 6:31 PM")
        #expect(stale.olderTexts(level: 0).isEmpty)
    }

    @Test func oneToolOrNone() {
        let claude = tool(.claudeCode, minutesOld: 50)
        #expect(WidgetAsOfLine.make([claude]) == WidgetAsOfLine(shared: claude.display, older: []))
        #expect(WidgetAsOfLine.make([]) == WidgetAsOfLine(shared: nil, older: []))
    }
}
