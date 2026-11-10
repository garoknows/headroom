import AppKit
import SwiftUI

/// How the app puts SwiftUI into windows and the popover. The layout tests and the docs renders
/// call the same functions, so they measure exactly what the app shows.
@MainActor
public enum WindowFactory {
    public static func makeWindow<V: View>(title: String, root: V) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    /// The popover follows its content's height, so it has no empty space below the card.
    public static func makePopover<V: View>(root: V) -> NSPopover {
        let hosting = NSHostingController(rootView: root)
        // Without this the popover keeps AppKit's default size and the card stretches to fill it.
        hosting.sizingOptions = [.preferredContentSize]
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = hosting
        return p
    }
}

/// Opens a window or the popover offscreen and reports what it really looks like: the window's
/// size, each layout probe's frame and a picture. Used by the layout tests and the docs renders.
@MainActor
public enum WindowHarness {
    public struct Result {
        public var contentSize: CGSize
        /// The size the content asks for (NSView.fittingSize). Its width must fit the window.
        public var fittingSize: CGSize
        /// The width that can be seen: the window's width minus a scroll bar that takes space.
        public var visibleWidth: CGFloat
        public var frames: [String: CGRect]
        /// The window as it looks, title bar included.
        public var image: NSBitmapImageRep?
        /// For a scrolling window, all of its content in one picture.
        public var fullImage: NSBitmapImageRep? = nil
    }

    /// `legacyScrollers` draws scroll bars the way "Show scroll bars: Always" does (they take
    /// room instead of floating over the content), as on a Mac with a mouse plugged in.
    public static func window<V: View>(_ root: V, title: String = "", dark: Bool, legacyScrollers: Bool = false) -> Result {
        _ = NSApplication.shared
        let recorder = LayoutRecorder()
        let w = WindowFactory.makeWindow(title: title, root: root.environment(\.layoutRecorder, recorder))
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        let result = settle(w, recorder: recorder, legacyScrollers: legacyScrollers)
        w.close()
        return result
    }

    public static func popover<V: View>(_ root: V, dark: Bool) -> Result {
        _ = NSApplication.shared
        let recorder = LayoutRecorder()
        let p = WindowFactory.makePopover(root: root.environment(\.layoutRecorder, recorder))
        p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        p.animates = false
        let anchorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        anchorWindow.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        anchorWindow.orderFrontRegardless()
        let anchor = NSView(frame: NSRect(x: 190, y: 880, width: 20, height: 20))
        anchorWindow.contentView?.addSubview(anchor)
        p.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        var result = Result(contentSize: .zero, fittingSize: .zero, visibleWidth: 0, frames: [:], image: nil)
        if let w = p.contentViewController?.view.window {
            result = settle(w, recorder: recorder, legacyScrollers: false)
            result.contentSize = p.contentSize
        }
        p.close()
        anchorWindow.close()
        return result
    }

    private static func settle(_ w: NSWindow, recorder: LayoutRecorder, legacyScrollers: Bool) -> Result {
        guard let view = w.contentViewController?.view ?? w.contentView else {
            return Result(contentSize: .zero, fittingSize: .zero, visibleWidth: 0, frames: [:], image: nil)
        }
        w.orderFrontRegardless()
        var scrollerWidth: CGFloat = 0
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            if legacyScrollers {
                for s in scrollViews(in: view) where s.hasVerticalScroller {
                    s.scrollerStyle = .legacy
                    scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
                }
            }
        }
        view.layoutSubtreeIfNeeded()
        // The whole window with its title bar if AppKit will draw it, otherwise the content.
        let drawn = w.contentView?.superview ?? view
        let image = snapshot(drawn) ?? snapshot(view)
        // Everything below the visible part of a scrolling window, drawn in one long picture.
        let full = scrollViews(in: view).first?.documentView.flatMap(snapshot).flatMap { onBackground($0, of: w) }
        // Probe frames are in window coordinates (top left, title bar included); make them
        // relative to the content view, so 0...width is exactly what the window shows.
        let inWindow = view.convert(view.bounds, to: nil)
        let top = w.frame.height - inWindow.maxY
        let frames = recorder.frames.mapValues { $0.offsetBy(dx: -inWindow.minX, dy: -top) }
        w.orderOut(nil)
        return Result(contentSize: view.frame.size, fittingSize: view.fittingSize, visibleWidth: view.frame.width - scrollerWidth,
                      frames: frames, image: image, fullImage: full)
    }

    /// The scrolled content has no background of its own; put the window's behind it.
    static func onBackground(_ rep: NSBitmapImageRep, of w: NSWindow) -> NSBitmapImageRep? {
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return rep }
        out.size = rep.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        w.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: rep.size).fill()
        }
        rep.draw(in: NSRect(origin: .zero, size: rep.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    /// The view drawn at 2x (Retina) whatever the offscreen window's own scale is.
    static func snapshot(_ v: NSView) -> NSBitmapImageRep? {
        guard v.bounds.width > 0, v.bounds.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2), pixelsHigh: Int(v.bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = v.bounds.size
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }

    static func scrollViews(in v: NSView) -> [NSScrollView] {
        ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrollViews)
    }

    /// Every probe that sticks out past the left edge or past the visible right edge, as text.
    public static func overflows(_ r: Result, tolerance: CGFloat = 0.5) -> [String] {
        var problems: [String] = []
        if r.fittingSize.width > r.contentSize.width + tolerance {
            problems.append("the content asks for \(Int(r.fittingSize.width)) points but the window is \(Int(r.contentSize.width)) wide")
        }
        return problems + r.frames.sorted { $0.key < $1.key }.compactMap { name, f in
            (f.minX < -tolerance || f.maxX > r.visibleWidth + tolerance)
                ? "\(name) spans x \(Int(f.minX.rounded()))...\(Int(f.maxX.rounded())) but the visible width is \(Int(r.visibleWidth))"
                : nil
        }
    }

    public static func png(_ rep: NSBitmapImageRep?) -> Data? {
        rep?.representation(using: .png, properties: [:])
    }
}
