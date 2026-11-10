import AppKit
import SwiftUI
import Testing
import WiggleroomCore
import WiggleroomUI
import WiggleroomWindows

// Lesson 26: every window and the popover are opened offscreen at their real size, exactly as
// the app opens them (WindowFactory), and nothing may be wider than what can be seen.
// Wiggleroom 0.1.0's setup window failed this: its content was laid out 756 points wide in a
// 620-point window, so 68 points were cut off each side.

@MainActor
@Suite(.serialized) struct WindowLayoutTests {
    nonisolated static let schemes = [false, true]   // light, dark

    @Test(arguments: schemes, [false, true])
    func setupWindowFitsItsWindow(dark: Bool, legacyScrollers: Bool) {
        // The states include the longest Connect message (a long file path) and the unsigned note.
        // (Larger Dynamic Type sizes don't change these macOS windows: measured identical.)
        for (state, model) in PreviewStates.models() {
            let r = WindowHarness.window(SetupView(model: model, sample: PreviewStates.bothLimits, done: {}),
                                         dark: dark, legacyScrollers: legacyScrollers)
            #expect(r.contentSize.width == WindowSizes.setup.width, "setup (\(state)) window is \(r.contentSize.width) wide")
            #expect(r.frames["setup: content"] != nil, "the setup content probe never reported")
            #expect(WindowHarness.overflows(r).isEmpty, "setup (\(state)): \(WindowHarness.overflows(r))")
        }
    }

    /// Each picture is laid out (not only drawn) no wider than the room it's given: the width of
    /// the content, which is less when scroll bars take space.
    @Test func setupPicturesAreLaidOutInsideTheContent() {
        let r = WindowHarness.window(SetupView(model: PreviewWindowModel(), sample: PreviewStates.bothLimits, done: {}), dark: false)
        guard let room = r.frames["setup: content"] else { Issue.record("the setup content probe never reported"); return }
        for n in 1...3 {
            // Where the picture is laid out, and where it is actually drawn after scaling.
            for name in ["setup: picture \(n)", "setup: picture \(n) drawn"] {
                let f = r.frames[name]
                #expect(f != nil, "\(name) probe never reported")
                if let f {
                    #expect(f.minX >= room.minX - 0.5 && f.maxX <= room.maxX + 0.5,
                            "\(name) spans x \(f.minX)...\(f.maxX); the content spans \(room.minX)...\(room.maxX)")
                }
            }
        }
        // The widest picture (700 points) is scaled down to fill the room exactly, not cut off.
        let laidOut = r.frames["setup: picture 3"]?.width ?? 0
        let drawn = r.frames["setup: picture 3 drawn"]?.width ?? 0
        #expect(abs(drawn - laidOut) < 1 && abs(laidOut - room.width) < 1,
                "picture 3 is laid out \(laidOut) wide and drawn \(drawn) wide; the content is \(room.width) wide (window \(r.contentSize.width), visible \(r.visibleWidth))")
    }

    @Test(arguments: schemes, [false, true])
    func settingsWindowFitsItsWindow(dark: Bool, legacyScrollers: Bool) {
        for (state, model) in PreviewStates.models() {
            let r = WindowHarness.window(SettingsView(model: model, openSetup: {}), dark: dark, legacyScrollers: legacyScrollers)
            #expect(r.contentSize.width == WindowSizes.settings.width, "Settings (\(state)) window is \(r.contentSize.width) wide")
            #expect(r.frames["settings: content"] != nil && r.frames["settings: data buttons"] != nil, "the Settings probes never reported")
            #expect(WindowHarness.overflows(r).isEmpty, "Settings (\(state)): \(WindowHarness.overflows(r))")
        }
    }

    /// The popover is as tall as its content: one row and no gap for a weekly-only plan.
    @Test(arguments: schemes)
    func popoverSizesToItsContent(dark: Bool) {
        var heights: [String: CGFloat] = [:]
        for (name, display) in [("weekly-only", PreviewStates.weeklyOnly), ("both", PreviewStates.bothLimits)] {
            let model = PreviewWindowModel(display: display)
            let r = WindowHarness.popover(PopoverView(model: model, openSettings: {}), dark: dark)
            #expect(WindowHarness.overflows(r).isEmpty, "popover (\(name)): \(WindowHarness.overflows(r))")
            #expect(r.contentSize.width == WindowSizes.popoverWidth)
            // The card is shown at its natural height, not stretched to fill the popover.
            let natural = NSHostingView(rootView: UsageCard(content: .usage(display), layout: .popover, live: true)
                .frame(width: WindowSizes.popoverWidth - 32).fixedSize(horizontal: false, vertical: true)).fittingSize.height
            let card = r.frames["popover: card"]?.height ?? .infinity
            #expect(card <= natural + 1, "popover (\(name)): the card is \(card) tall but needs only \(natural)")
            // And the popover has no empty space around its content.
            let content = r.frames["popover: content"]?.height ?? .infinity
            #expect(abs(r.contentSize.height - content) <= 1, "popover (\(name)) is \(r.contentSize.height) tall for \(content) of content")
            heights[name] = r.contentSize.height
        }
        if let one = heights["weekly-only"], let two = heights["both"] {
            #expect(one < two, "a weekly-only popover (\(one)) should be shorter than one with both limits (\(two))")
        }
    }
}
