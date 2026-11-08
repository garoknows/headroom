import Foundation
import Testing
@testable import HeadroomCore

@Suite struct ConnectionTests {
    @Test func refusesTemporaryAndMissingLocations() {
        let exists: (String) -> Bool = { _ in true }
        #expect(Connection.locationProblem(executablePath: "/private/var/folders/x/AppTranslocation/ABC/d/Headroom.app/Contents/Helpers/headroom-statusline", fileExists: exists) != nil)
        #expect(Connection.locationProblem(executablePath: "/Volumes/Headroom/Headroom.app/Contents/Helpers/headroom-statusline", fileExists: exists) != nil)
        #expect(Connection.locationProblem(executablePath: "/Applications/Headroom.app/Contents/Helpers/headroom-statusline", fileExists: exists) == nil)
        #expect(Connection.locationProblem(executablePath: "/Applications/Headroom.app/Contents/Helpers/headroom-statusline", fileExists: { _ in false }) != nil)
    }

    @Test func connectRefusesFromATemporaryCopyAndChangesNothing() {
        let paths = HeadroomPaths(home: makeTempHome())
        let c = Connection(settingsURL: paths.claudeSettings,
                           executablePath: "/private/var/folders/x/AppTranslocation/A/d/Headroom.app/Contents/Helpers/headroom-statusline")
        if case .done = c.connect() { Issue.record("should refuse") }
        #expect(!FileManager.default.fileExists(atPath: paths.claudeSettings.path))
    }

    @Test func connectAndDisconnectOnATempHome() throws {
        let home = makeTempHome()
        let paths = HeadroomPaths(home: home)
        // A stand-in for the helper inside the app.
        let helper = home.appendingPathComponent("Fake.app/Contents/Helpers/headroom-statusline")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        chmod(helper.path, 0o755)
        let c = Connection(settingsURL: paths.claudeSettings, executablePath: helper.path)
        #expect(c.status() == .noSettingsFile)
        guard case .done = c.connect() else { Issue.record("connect failed"); return }
        #expect(c.status() == .connected(StatuslineCommand(executablePath: helper.path, previous: nil)))
        guard case .done = c.disconnect() else { Issue.record("disconnect failed"); return }
        #expect(c.status() == .notConnected(hasOtherStatusLine: false))
        if case .refused = c.disconnect() {} else { Issue.record("second disconnect should be refused") }
    }

    @Test func eraseRemovesOnlyHeadroomData() throws {
        let home = makeTempHome()
        let paths = HeadroomPaths(home: home)
        StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: Date())
        let group = home.appendingPathComponent("group", isDirectory: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: group.appendingPathComponent(AppGroupFiles.snapshotName))
        try Data("other app".utf8).write(to: group.appendingPathComponent("other.txt"))
        // Another app's similarly named folder must survive (DECISIONS D6).
        let other = home.appendingPathComponent("Library/Application Support/Headroom", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let problems = DataEraser.eraseAll(paths: paths, appGroupFolder: group)
        #expect(problems.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.supportFolder.path))
        #expect(!FileManager.default.fileExists(atPath: group.appendingPathComponent(AppGroupFiles.snapshotName).path))
        #expect(FileManager.default.fileExists(atPath: group.appendingPathComponent("other.txt").path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func publishNeverReplacesGoodWithBad() throws {
        let group = makeTempHome()
        let now = Date(timeIntervalSince1970: 1_799_990_000)
        let good = UsageSnapshot(updatedAt: now, limits: [LimitWindow(id: "seven_day", usedPercent: 40, resetsAt: now.addingTimeInterval(3600))])
        #expect(AppGroupFiles.publish(good, to: group, now: now))
        #expect(SecureFile.permissions(of: group.appendingPathComponent(AppGroupFiles.snapshotName)) == 0o600)
        #expect(!AppGroupFiles.publish(nil, to: group, now: now))
        let bad = UsageSnapshot(updatedAt: now.addingTimeInterval(5), limits: [LimitWindow(id: "seven_day", usedPercent: 900, resetsAt: nil)])
        #expect(!AppGroupFiles.publish(bad, to: group, now: now))
        #expect(!AppGroupFiles.publish(good, to: group, now: now)) // same data: no rewrite, no reload
        #expect(AppGroupFiles.readSnapshot(in: group, now: now) == good)
        // A corrupt file in the group is replaced by good data.
        try Data("{".utf8).write(to: group.appendingPathComponent(AppGroupFiles.snapshotName))
        #expect(AppGroupFiles.readSnapshot(in: group, now: now) == nil)
        #expect(AppGroupFiles.publish(good, to: group, now: now))
    }
}
