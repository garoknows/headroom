import AppKit
import WiggleroomCore
import SwiftUI

/// Wiggleroom runs in the background (no Dock icon). Opening the app again shows Settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        let mb = MenuBarController(model: model, openSettings: { [weak self] in self?.showSettings() })
        menuBar = mb
        mb.setVisible(model.showMenuBar)
        model.onMenuBarChange = { [weak mb] on in mb?.setVisible(on) }
        if !model.setupDone {
            showSetup()
        } else if model.connectedElsewhere {
            // The app was moved since connecting; Settings explains and offers to update.
            showSettings()
        }
    }

    /// Double-clicking Wiggleroom while it's running opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showSettings() {
        model.refreshConnection()
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Wiggleroom Settings", root: SettingsView(model: model, openSetup: { [weak self] in self?.showSetup() }))
        }
        present(settingsWindow)
    }

    func showSetup() {
        if setupWindow == nil {
            setupWindow = makeWindow(title: "Set Up Wiggleroom", root: SetupView(model: model, done: { [weak self] in
                self?.setupWindow?.close()
            }))
        }
        present(setupWindow)
    }

    private func makeWindow<V: View>(title: String, root: V) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    private func present(_ w: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }
}
