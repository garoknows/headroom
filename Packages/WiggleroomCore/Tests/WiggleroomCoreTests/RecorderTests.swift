import Foundation
import Testing
@testable import WiggleroomCore

@Suite struct RecorderTests {
    let now = Date(timeIntervalSince1970: 1_799_990_000)

    /// Collects every key and every string value anywhere in a JSON value.
    func walk(_ v: Any, keys: inout Set<String>, strings: inout [String]) {
        if let d = v as? [String: Any] {
            for (k, x) in d { keys.insert(k); walk(x, keys: &keys, strings: &strings) }
        } else if let a = v as? [Any] {
            a.forEach { walk($0, keys: &keys, strings: &strings) }
        } else if let s = v as? String {
            strings.append(s)
        }
    }

    @Test func outputHasOnlyAllowedKeysAndNoOtherData() throws {
        let home = makeTempHome()
        let paths = WiggleroomPaths(home: home)
        #expect(StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now) == .wrote)
        let data = try #require(FileManager.default.contents(atPath: paths.usageFile.path))
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(top.keys) == UsageSnapshot.allowedKeys)
        let limits = try #require(top["limits"] as? [[String: Any]])
        for l in limits { #expect(Set(l.keys).isSubset(of: UsageSnapshot.allowedLimitKeys)) }
        var keys = Set<String>(), strings: [String] = []
        walk(top, keys: &keys, strings: &strings)
        #expect(keys.isSubset(of: UsageSnapshot.allowedKeys.union(UsageSnapshot.allowedLimitKeys)))
        // The only strings are limit names.
        #expect(Set(strings) == ["five_hour", "seven_day", "spend_limit"])
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["SECRET", "secret", "payroll", "private/var", "314.12", "500", "monthly", "12.3456", "example.com"] {
            #expect(!text.contains(secret), "found \(secret) in \(text)")
        }
    }

    @Test func filePermissionsArePrivate() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now)
        #expect(SecureFile.permissions(of: paths.usageFile) == 0o600)
        #expect(SecureFile.permissions(of: paths.supportFolder) == 0o700)
        // An existing folder that is too open gets tightened.
        chmod(paths.supportFolder.path, 0o755)
        StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now.addingTimeInterval(5))
        #expect(SecureFile.permissions(of: paths.supportFolder) == 0o700)
        #expect(SecureFile.permissions(of: paths.usageFile) == 0o600)
    }

    @Test func noRateLimitsKeepsTheLastGoodFile() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now)
        let before = try #require(FileManager.default.contents(atPath: paths.usageFile.path))
        #expect(StatuslineRecorder.record(payload: Fixture.data("no-rate-limits.json"), paths: paths, now: now.addingTimeInterval(60)) == .nothingToRecord)
        #expect(StatuslineRecorder.record(payload: Data("garbage".utf8), paths: paths, now: now.addingTimeInterval(60)) == .nothingToRecord)
        #expect(FileManager.default.contents(atPath: paths.usageFile.path) == before)
    }

    @Test func nothingIsCreatedWithoutRateLimits() {
        let paths = WiggleroomPaths(home: makeTempHome())
        StatuslineRecorder.record(payload: Fixture.data("no-rate-limits.json"), paths: paths, now: now)
        #expect(!FileManager.default.fileExists(atPath: paths.supportFolder.path))
    }

    @Test func corruptFileOnDiskIsReplacedByGoodData() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        try SecureFile.ensurePrivateFolder(paths.supportFolder)
        try Data("{ half a fi".utf8).write(to: paths.usageFile)
        #expect(StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now) == .wrote)
        let s = try #require(SecureFile.readSmallFile(paths.usageFile).flatMap(UsageSnapshot.decode))
        #expect(s.limit("seven_day")?.usedPercent == 41.2)
    }

    @Test func unwritableFolderFailsQuietly() throws {
        let home = makeTempHome()
        let paths = WiggleroomPaths(home: home)
        // A plain file where the folder should be: Wiggleroom must not crash or follow it.
        try FileManager.default.createDirectory(at: paths.supportFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: paths.supportFolder)
        #expect(StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now) == .failed)
    }

    @Test func symlinkedDataFileIsNotFollowed() throws {
        let home = makeTempHome()
        let paths = WiggleroomPaths(home: home)
        try SecureFile.ensurePrivateFolder(paths.supportFolder)
        let elsewhere = home.appendingPathComponent("elsewhere.txt")
        try Data("keep me".utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: paths.usageFile, withDestinationURL: elsewhere)
        StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now)
        // The rename replaces the link itself; the file it pointed to is untouched.
        #expect(FileManager.default.contents(atPath: elsewhere.path) == Data("keep me".utf8))
    }

    @Test func atomicWriteLeavesNoTempFiles() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        for i in 0..<20 {
            StatuslineRecorder.record(payload: Fixture.data("full-payload.json"), paths: paths, now: now.addingTimeInterval(Double(i)))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: paths.supportFolder.path)
        #expect(Set(names) == ["usage.json", ".usage.lock"])
    }

    @Test func concurrentWritersAlwaysLeaveAValidFile() async throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        let payload = Fixture.data("full-payload.json")
        let base = now
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                group.addTask { StatuslineRecorder.record(payload: payload, paths: paths, now: base.addingTimeInterval(Double(i))) }
            }
        }
        let s = try #require(SecureFile.readSmallFile(paths.usageFile).flatMap(UsageSnapshot.decode))
        #expect(SnapshotPolicy.isPlausible(s, now: base.addingTimeInterval(60)))
    }
}
