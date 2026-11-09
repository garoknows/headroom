import Foundation

enum HelperLocation {
    /// The status line program, shipped next to the app's own executable (Contents/MacOS).
    static var executablePath: String {
        let dir = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
        return dir.appendingPathComponent("headroom-statusline").path
    }
}
