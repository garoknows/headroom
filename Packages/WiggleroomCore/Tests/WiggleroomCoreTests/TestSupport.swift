import Foundation
@testable import WiggleroomCore

enum Fixture {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static func data(_ name: String) -> Data {
        // A missing fixture is a broken test, not an empty input.
        guard let d = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path) else {
            fatalError("missing fixture \(name)")
        }
        return d
    }
}

/// Where tests may create files. The direct test runner points this at the build folder,
/// because a sandboxed shell can't write to the system temp folder.
func testTempRoot() -> URL {
    let path = ProcessInfo.processInfo.environment["WIGGLEROOM_TEST_TMP"] ?? NSTemporaryDirectory()
    return URL(fileURLWithPath: path, isDirectory: true)
}

/// A fresh, empty folder that stands in for a home folder. Never the real one.
func makeTempHome() -> URL {
    let base = testTempRoot()
        .appendingPathComponent("wiggleroom-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

/// A date from local wall-clock parts in a given time zone.
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, tz: String) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

let vegas = "America/Los_Angeles"   // Las Vegas uses Pacific time
let tokyo = "Asia/Tokyo"
let utc = "UTC"
