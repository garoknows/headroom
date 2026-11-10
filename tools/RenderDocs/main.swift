// Renders Wiggleroom's widget and setup pictures offscreen to PNG files, for checking by eye and
// for the docs. Uses the same SwiftUI views the widget and the app use, with invented numbers.
// Usage: tools/render-docs.sh [output folder]   (default docs/images)

import AppKit
import WiggleroomCore
import WiggleroomUI
import WiggleroomWindows
import SwiftUI

let args = Array(CommandLine.arguments.dropFirst())

// `render-docs --iconset <folder>` writes the app icon PNGs that tools/make-icns.py packs.
if args.first == "--iconset", args.count == 2 {
    let dir = URL(fileURLWithPath: args[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    MainActor.assumeIsolated {
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                let r = ImageRenderer(content: WiggleroomMark(iconGrid: true).frame(width: px, height: px))
                r.scale = 1
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                let data = NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!
                try! data.write(to: dir.appendingPathComponent(name))
            }
        }
    }
    print("wrote iconset to \(dir.path)")
    exit(0)
}

/// The windows and the popover as the app opens them (WindowFactory), at their real size, drawn
/// by AppKit. Lesson 26: each picture is checked by eye; the layout tests check the numbers.
@MainActor func renderWindows(to dir: URL, all: Bool) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func write(_ rep: NSBitmapImageRep?, _ name: String) {
        guard let data = WindowHarness.png(rep) else { print("FAILED \(name)"); return }
        try! data.write(to: dir.appendingPathComponent(name + ".png"))
        print("wrote \(name).png \(rep!.pixelsWide)x\(rep!.pixelsHigh)")
    }
    let models = PreviewStates.models()
    for (dark, sname) in [(false, "light"), (true, "dark")] {
        // The docs show the first-run setup window; the check renders show every state.
        for (state, model) in all ? models : [models[0]] {
            let r = WindowHarness.window(SetupView(model: model, sample: PreviewStates.bothLimits, done: {}), title: "Set Up Wiggleroom", dark: dark)
            write(r.image, all ? "window-setup-\(state)-\(sname)" : "window-setup-\(sname)")
            if all { write(r.fullImage, "window-setup-\(state)-\(sname)-full") }
        }
        guard all else { continue }
        for (state, model) in models {
            let r = WindowHarness.window(SettingsView(model: model, openSetup: {}), title: "Wiggleroom Settings", dark: dark)
            write(r.image, "window-settings-\(state)-\(sname)")
            write(r.fullImage, "window-settings-\(state)-\(sname)-full")
        }
        let legacy = WindowHarness.window(SettingsView(model: models[1].1, openSetup: {}), title: "Wiggleroom Settings", dark: dark, legacyScrollers: true)
        write(legacy.image, "window-settings-connected-\(sname)-scrollbars-always")
        let legacySetup = WindowHarness.window(SetupView(model: models[0].1, sample: PreviewStates.bothLimits, done: {}), title: "Set Up Wiggleroom", dark: dark, legacyScrollers: true)
        write(legacySetup.image, "window-setup-first-run-\(sname)-scrollbars-always")
        // The popover's session countdown ticks from the real clock, so these use invented
        // numbers around the real time instead of the fixed January 2027 moment.
        let realNow = Date()
        let liveBoth = UsageFormatter.display(SampleData.snapshot(now: realNow, age: 4 * 60), context: DisplayContext(now: realNow))
        var weekOnly = SampleData.snapshot(now: realNow, age: 3 * 60); weekOnly.limits.removeFirst()
        let liveWeekly = UsageFormatter.display(weekOnly, context: DisplayContext(now: realNow))
        for (state, display) in [("weekly-only", liveWeekly), ("both-limits", liveBoth)] {
            let r = WindowHarness.popover(PopoverView(model: PreviewWindowModel(display: display), openSettings: {}), dark: dark)
            write(r.image, "popover-\(state)-\(sname)")
        }
    }
}

// `render-docs --windows <folder>` renders every window state, for checking by eye.
if args.first == "--windows", args.count == 2 {
    MainActor.assumeIsolated { renderWindows(to: URL(fileURLWithPath: args[1], isDirectory: true), all: true) }
    exit(0)
}

let out = URL(fileURLWithPath: args.first ?? "docs/images", isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// A fixed moment and place, so the pictures are the same on every run:
// Thursday Jan 14, 2027, 2:45 PM in Las Vegas (Pacific time), 12-hour clock.
let tz = TimeZone(identifier: "America/Los_Angeles")!
var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
let now = cal.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 14, minute: 45))!
let ctx = DisplayContext(now: now, timeZone: tz, clock: .twelveHour)

func display(_ s: UsageSnapshot) -> UsageDisplay { UsageFormatter.display(s, context: ctx) }

let normal = display(SampleData.snapshot(now: now, timeZone: tz, age: 4 * 60))
let stale = display(SampleData.snapshot(now: now, timeZone: tz, age: 47 * 60))
let veryStale = display(SampleData.snapshot(now: now, timeZone: tz, age: 7 * 3600))
let warning = display(SampleData.snapshot(now: now, timeZone: tz, session: 64, week: 82, age: 2 * 60))
let critical = display(SampleData.snapshot(now: now, timeZone: tz, session: 97, week: 93, age: 60))
let resetPassed: UsageDisplay = {
    var s = SampleData.snapshot(now: now, timeZone: tz, age: 75 * 60)
    s.limits[0].resetsAt = now.addingTimeInterval(-20 * 60)   // the 5-hour window reset 20 minutes ago
    return display(s)
}()
let weeklyOnly: UsageDisplay = {
    var s = SampleData.snapshot(now: now, timeZone: tz, age: 3 * 60)
    s.limits.removeFirst()
    return display(s)
}()

@MainActor func save<V: View>(_ view: V, _ name: String, scheme: ColorScheme) {
    let r = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    r.scale = 2
    guard let cg = r.cgImage else { print("FAILED \(name)"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    // PNGs carry no title, author or software text (lesson 4).
    guard let data = rep.representation(using: .png, properties: [:]) else { print("FAILED \(name)"); return }
    try! data.write(to: out.appendingPathComponent(name + ".png"))
    print("wrote \(name).png \(cg.width)x\(cg.height)")
}

/// The widget as Notification Center shows it: the card on its own rounded background.
@MainActor func widget(_ content: CardContent, _ layout: CardLayout, _ scheme: ColorScheme) -> some View {
    let size = layout == .small ? CGSize(width: 170, height: 170) : CGSize(width: 364, height: 170)
    return UsageCard(content: content, layout: layout, live: false)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette(scheme).card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.gray.opacity(0.18), lineWidth: 0.5))
        .padding(12)
}

let states: [(String, CardContent)] = [
    ("normal", .usage(normal)), ("stale", .usage(stale)), ("very-stale", .usage(veryStale)),
    ("reset-passed", .usage(resetPassed)), ("warning", .usage(warning)), ("critical", .usage(critical)),
    ("weekly-only", .usage(weeklyOnly)), ("empty", .empty), ("unavailable", .unavailable),
]

MainActor.assumeIsolated {
    for (scheme, sname) in [(ColorScheme.light, "light"), (.dark, "dark")] {
        for (state, content) in states {
            save(widget(content, .small, scheme), "widget-small-\(sname)-\(state)", scheme: scheme)
            save(widget(content, .medium, scheme), "widget-medium-\(sname)-\(state)", scheme: scheme)
        }
        save(MenuBarPicture().padding(16), "setup-1-menu-bar-\(sname)", scheme: scheme)
        save(NotificationCenterPicture().padding(16), "setup-2-notification-center-\(sname)", scheme: scheme)
        save(WidgetGalleryPicture(sample: normal).padding(16), "setup-3-widget-gallery-\(sname)", scheme: scheme)
    }
    save(WiggleroomMark(iconGrid: true).frame(width: 512, height: 512), "icon", scheme: .light)
    renderWindows(to: out, all: false)
}
