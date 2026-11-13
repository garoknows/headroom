import AppKit
import Combine
import WiggleroomCore
import WiggleroomWindows
import WiggleroomUI
import SwiftUI

/// The optional menu bar item (off by default): a small gauge and the weekly percent.
/// Clicking it opens a popover with the medium card, Settings… and Quit.
@MainActor
final class MenuBarController {
    private let model: AppModel
    private let openSettings: () -> Void
    private var item: NSStatusItem?
    private var popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        popover = WindowFactory.makePopover(root: PopoverView(model: model, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }))
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateButton() } }
        }.store(in: &cancellables)
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.target = self
            i.button?.action = #selector(toggle)
            i.button?.imagePosition = .imageLeading
            item = i
            updateButton()
        } else if !visible, let i = item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
    }

    private func updateButton() {
        guard let button = item?.button else { return }
        let tools = model.toolDisplays
        let picked = model.menuBarChoice.pick(from: tools)
        let row = picked?.display.primary
        let text = MenuBarText.make(choice: model.menuBarChoice, picked: picked)
        button.image = Self.gauge(fraction: (row?.percent == nil ? 0 : row!.usedPercent) / 100)
        button.title = text.title
        button.toolTip = text.tooltip
        button.setAccessibilityLabel(text.tooltip)
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// A tiny version of the app icon as a template image: an outlined bar, filled from the
    /// bottom by `fraction`, with a ceiling line above. macOS tints it for light and dark menu bars.
    static func gauge(fraction: Double) -> NSImage {
        let img = NSImage(size: NSSize(width: 12, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 14, width: 10, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            let body = NSRect(x: 2.5, y: 1, width: 7, height: 11)
            let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.8, yRadius: 1.8)
            outline.lineWidth = 1
            NSColor.black.setStroke()
            outline.stroke()
            let f = max(0, min(1, fraction))
            if f > 0 {
                let fill = NSRect(x: body.minX, y: body.minY, width: body.width, height: max(1.5, body.height * f))
                NSBezierPath(roundedRect: fill, xRadius: 1.8, yRadius: 1.8).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
