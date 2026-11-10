import AppKit
import WiggleroomCore

// `Wiggleroom --disconnect` puts the user's previous Claude Code status line back and exits.
// Homebrew's uninstall runs it, so removing Wiggleroom never leaves Claude Code pointing at a
// deleted program. It always exits 0 so an uninstall can't get stuck on it.
if CommandLine.arguments.contains("--disconnect") {
    let paths = WiggleroomPaths.currentUser()
    let connection = Connection(settingsURL: paths.claudeSettings, backupFolder: paths.backupFolder, executablePath: HelperLocation.executablePath)
    if case .connected = connection.status() {
        switch connection.disconnect() {
        case .done(let summary, _): print("Wiggleroom: \(summary)")
        case .refused(let why): print("Wiggleroom: \(why)")
        }
    } else {
        print("Wiggleroom: not connected to Claude Code; nothing to do.")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
