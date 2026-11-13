import Foundation
import Testing
@testable import WiggleroomCore

/// 0.2.1: the popover and the menu bar use one order, the two-tool popover is compact, and the
/// footer names every watched tool.
@Suite struct PopoverOrderTests {
    let now = date(2027, 1, 14, 14, 45, tz: vegas)
    var ctx: DisplayContext { DisplayContext(now: now, timeZone: TimeZone(identifier: vegas)!, clock: .twelveHour) }

    func tool(_ t: Tool, session: Double?, week: Double?) -> ToolDisplay {
        var limits: [LimitWindow] = []
        if let session { limits.append(LimitWindow(id: "five_hour", usedPercent: session, resetsAt: now.addingTimeInterval(3600))) }
        if let week { limits.append(LimitWindow(id: "seven_day", usedPercent: week, resetsAt: now.addingTimeInterval(4 * 86400))) }
        return ToolDisplay(tool: t, display: UsageFormatter.display(UsageSnapshot(updatedAt: now, limits: limits), context: ctx))
    }

    @Test func highestWeeklyPercentComesFirst() {
        // Claude Code's 5-hour limit is closer to running out, but the order goes by the weekly percent.
        let claude = tool(.claudeCode, session: 95, week: 41)
        let codex = tool(.codex, session: 5, week: 60)
        #expect(ToolDisplay.highestFirst([claude, codex]).map(\.tool) == [.codex, .claudeCode])
        #expect(ToolDisplay.highestFirst([codex, claude]).map(\.tool) == [.codex, .claudeCode])
        // A tie goes to Claude Code.
        #expect(ToolDisplay.highestFirst([tool(.codex, session: 1, week: 41), tool(.claudeCode, session: 1, week: 41)]).map(\.tool) == [.claudeCode, .codex])
        // A tool without numbers goes last.
        #expect(ToolDisplay.highestFirst([tool(.claudeCode, session: nil, week: nil), tool(.codex, session: nil, week: 3)]).map(\.tool) == [.codex, .claudeCode])
    }

    @Test func theMenuBarToolIsAlwaysTheTopCard() {
        let combos: [[ToolDisplay]] = [
            [tool(.claudeCode, session: 95, week: 41), tool(.codex, session: 5, week: 60)],
            [tool(.claudeCode, session: 20, week: 30), tool(.codex, session: 0, week: 0)],   // Claude Code ahead, Codex at 0
            [tool(.codex, session: 1, week: 41), tool(.claudeCode, session: 1, week: 41)],
            [tool(.claudeCode, session: nil, week: nil), tool(.codex, session: 88, week: 10)],
            [tool(.claudeCode, session: 50, week: 50)],
        ]
        for tools in combos {
            for choice in MenuBarChoice.allCases {
                let order = choice.popoverOrder(tools)
                #expect(Set(order.map(\.tool)) == Set(tools.map(\.tool)), "the popover keeps every tool")
                #expect(order.count == tools.count)
                if let shown = choice.pick(from: tools) {
                    #expect(order.first?.tool == shown.tool, "\(choice): menu bar shows \(shown.tool), top card is \(String(describing: order.first?.tool))")
                }
            }
        }
    }

    @Test func highestUsesTheSameOrderAsThePopover() {
        let claude = tool(.claudeCode, session: 95, week: 41)
        let codex = tool(.codex, session: 5, week: 60)
        #expect(MenuBarChoice.highest.popoverOrder([claude, codex]).map(\.tool) == [.codex, .claudeCode])
        // Pinned to Claude Code: Claude Code on top, even though Codex's weekly is higher.
        #expect(MenuBarChoice.claudeCode.popoverOrder([codex, claude]).map(\.tool) == [.claudeCode, .codex])
        // Pinned to a tool that has no numbers: the rest keep the "Highest" order.
        #expect(MenuBarChoice.codex.popoverOrder([claude]).map(\.tool) == [.claudeCode])
    }
}

@Suite struct CompactPopoverTests {
    let now = date(2027, 1, 14, 14, 45, tz: vegas)
    var ctx: DisplayContext { DisplayContext(now: now, timeZone: TimeZone(identifier: vegas)!, clock: .twelveHour) }

    func codex(session: Double?, week: Double?, sessionReset: TimeInterval = 3600) -> ToolDisplay {
        var limits: [LimitWindow] = []
        if let session { limits.append(LimitWindow(id: "five_hour", usedPercent: session, resetsAt: now.addingTimeInterval(sessionReset), label: "5-hour", windowMinutes: 300)) }
        if let week { limits.append(LimitWindow(id: "seven_day", usedPercent: week, resetsAt: now.addingTimeInterval(4 * 86400), label: "This week", windowMinutes: 10080)) }
        return ToolDisplay(tool: .codex, display: UsageFormatter.display(UsageSnapshot(updatedAt: now, limits: limits), context: ctx))
    }

    @Test func weeklyRowOnlyWhileOtherLimitsAreLow() {
        #expect(codex(session: 0, week: 0).compactRows.map(\.id) == ["seven_day"])
        #expect(codex(session: 74.9, week: 12).compactRows.map(\.id) == ["seven_day"])
    }

    @Test func anotherLimitAt75OrMoreIsAddedAfterTheWeeklyRow() {
        #expect(codex(session: 75, week: 12).compactRows.map(\.id) == ["seven_day", "five_hour"])
        #expect(codex(session: 99.5, week: 91).compactRows.map(\.id) == ["seven_day", "five_hour"])
    }

    @Test func aLimitWhoseResetPassedIsNotAdded() {
        // 95% from a window that already reset is old news ("Waiting"), not a warning.
        #expect(codex(session: 95, week: 12, sessionReset: -60).compactRows.map(\.id) == ["seven_day"])
    }

    @Test func aToolWithoutAWeeklyLimitShowsItsFirstLimit() {
        #expect(codex(session: 10, week: nil).compactRows.map(\.id) == ["five_hour"])
        #expect(codex(session: nil, week: 30).compactRows.map(\.id) == ["seven_day"])
    }
}

@Suite struct WatcherSummaryTests {
    @Test func oneToolKeepsTheOldWording() {
        #expect(WatcherSummary.lines(tools: [.claudeCode], claudeCode: .watching, codex: .watching)
                == [WatcherLine(text: "Watching for new numbers from Claude Code", ok: true)])
        #expect(WatcherSummary.lines(tools: [.codex], claudeCode: .watching, codex: .watching)
                == [WatcherLine(text: "Watching for new numbers from Codex", ok: true)])
    }

    @Test func bothToolsWatchedIsOneShortLine() {
        // Short enough for one line in the 320-point popover.
        #expect(WatcherSummary.lines(tools: [.claudeCode, .codex], claudeCode: .watching, codex: .watching)
                == [WatcherLine(text: "Watching Claude Code and Codex", ok: true)])
    }

    @Test func aToolWithAProblemGetsItsOwnLine() {
        #expect(WatcherSummary.lines(tools: [.claudeCode, .codex], claudeCode: .watching, codex: .problem(WatcherSummary.codexNotFound))
                == [WatcherLine(text: "Not watching Codex: \(WatcherSummary.codexNotFound)", ok: false),
                    WatcherLine(text: "Watching for new numbers from Claude Code", ok: true)])
        #expect(WatcherSummary.lines(tools: [.claudeCode, .codex], claudeCode: .problem("the data folder can't be read"), codex: .problem(WatcherSummary.codexStopped))
                == [WatcherLine(text: "Not watching Claude Code: the data folder can't be read", ok: false),
                    WatcherLine(text: "Not watching Codex: \(WatcherSummary.codexStopped)", ok: false)])
        #expect(WatcherSummary.lines(tools: [.claudeCode], claudeCode: .starting, codex: .watching)
                == [WatcherLine(text: "Starting to watch Claude Code…", ok: false)])
    }

    @Test func aToolThatIsNotConnectedIsNotMentioned() {
        // Codex not connected: its watcher's state doesn't matter.
        #expect(WatcherSummary.lines(tools: [.claudeCode], claudeCode: .watching, codex: .problem(WatcherSummary.codexStopped))
                == [WatcherLine(text: "Watching for new numbers from Claude Code", ok: true)])
        // Nothing connected yet: Claude Code's watcher is what setup waits on.
        #expect(WatcherSummary.lines(tools: [], claudeCode: .watching, codex: .watching)
                == [WatcherLine(text: "Watching for new numbers from Claude Code", ok: true)])
    }
}
