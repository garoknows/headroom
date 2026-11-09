import AppKit
import HeadroomCore

// `Headroom --disconnect` puts the user's previous Claude Code status line back and exits.
// Homebrew's uninstall runs it, so removing Headroom never leaves Claude Code pointing at a
// deleted program. It always exits 0 so an uninstall can't get stuck on it.
if CommandLine.arguments.contains("--disconnect") {
    let paths = HeadroomPaths.currentUser()
    let connection = Connection(settingsURL: paths.claudeSettings, executablePath: HelperLocation.executablePath)
    if case .connected = connection.status() {
        switch connection.disconnect() {
        case .done(let summary, _): print("Headroom: \(summary)")
        case .refused(let why): print("Headroom: \(why)")
        }
    } else {
        print("Headroom: not connected to Claude Code; nothing to do.")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
