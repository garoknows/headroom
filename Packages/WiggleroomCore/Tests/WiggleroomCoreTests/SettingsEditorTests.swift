import Foundation
import Testing
@testable import WiggleroomCore

/// Every test here works on text in memory or on files in a fresh temp folder.
/// None of them ever opens the real ~/.claude/settings.json.
@Suite struct SettingsEditorTests {
    let exe = "/Applications/Wiggleroom.app/Contents/Helpers/wiggleroom-statusline"
    let exe2 = "/Volumes/My Apps/Wiggle'room.app/Contents/Helpers/wiggleroom-statusline"

    func text(_ r: Result<ClaudeSettingsEditor.Change, ClaudeSettingsEditor.Refusal>) throws -> String {
        switch r {
        case .success(let c): return String(decoding: c.newText, as: UTF8.self)
        case .failure(let f): Issue.record("refused: \(f)"); throw f
        }
    }
    func refusal(_ r: Result<ClaudeSettingsEditor.Change, ClaudeSettingsEditor.Refusal>) -> ClaudeSettingsEditor.Refusal? {
        if case .failure(let f) = r { return f }
        return nil
    }
    func json(_ s: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    func command(_ s: String) throws -> String? {
        ((try json(s))["statusLine"] as? [String: Any])?["command"] as? String
    }

    // MARK: Connect

    @Test func connectWithNoSettingsFile() throws {
        let out = try text(ClaudeSettingsEditor.connect(original: nil, executablePath: exe))
        let cmd = try #require(try command(out))
        #expect(StatuslineCommand.parse(cmd) == StatuslineCommand(executablePath: exe, previous: nil))
        #expect(((try json(out))["statusLine"] as? [String: Any])?["type"] as? String == "command")
    }

    @Test func connectWithNoStatusLineKeepsEverythingElseByteForByte() throws {
        let original = """
        {
          "model": "opus",
          "env": { "FOO": "bar", "URL": "https://example.com/a/b" },
          "permissions": {"allow": ["Bash(ls)"],   "deny": []},
          "number": 1.50e3
        }

        """
        let out = try text(ClaudeSettingsEditor.connect(original: Data(original.utf8), executablePath: exe))
        // Removing the inserted block gives back the exact original.
        let start = try #require(out.range(of: "\n  \"statusLine\""))
        let end = try #require(out.range(of: "},", range: start.upperBound..<out.endIndex))
        var back = out; back.removeSubrange(start.lowerBound..<end.upperBound)
        #expect(back == original)
        #expect(try command(out) == StatuslineCommand(executablePath: exe, previous: nil).commandLine)
        // Disconnect gives back the exact original too.
        let restored = try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8)))
        #expect(restored == original)
    }

    @Test func connectChainsAnExistingStatusLine() throws {
        let prev = #"bash ~/.claude/statusline.sh "$HOME" | sed 's/a/b/' # it's mine"#
        let original = "{\n\t\"statusLine\": {\n\t\t\"type\": \"command\",\n\t\t\"command\": \(ClaudeSettingsEditor.jsonString(prev)),\n\t\t\"padding\": 2\n\t},\n\t\"model\": \"sonnet\"\n}\n"
        let out = try text(ClaudeSettingsEditor.connect(original: Data(original.utf8), executablePath: exe2))
        let cmd = try #require(try command(out))
        let parsed = try #require(StatuslineCommand.parse(cmd))
        #expect(parsed.executablePath == exe2)
        #expect(parsed.previous == prev)
        #expect(((try json(out))["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
        #expect(out.contains("\t\t\"padding\": 2\n\t},\n\t\"model\": \"sonnet\"\n}\n"))
        // Disconnect puts back the very same text.
        #expect(try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8))) == original)
    }

    @Test func connectTwiceIsHarmlessAndMovingTheAppUpdatesThePath() throws {
        let once = try text(ClaudeSettingsEditor.connect(original: Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"echo hi\"}}".utf8), executablePath: exe))
        let twice = try text(ClaudeSettingsEditor.connect(original: Data(once.utf8), executablePath: exe))
        #expect(once == twice)
        let moved = try text(ClaudeSettingsEditor.connect(original: Data(once.utf8), executablePath: exe2))
        let movedCmd = try #require(try command(moved))
        let parsed = try #require(StatuslineCommand.parse(movedCmd))
        #expect(parsed.executablePath == exe2 && parsed.previous == "echo hi") // chain kept, never doubled
        #expect(try command(try text(ClaudeSettingsEditor.disconnect(original: Data(moved.utf8)))) == "echo hi")
    }

    @Test func disconnectKeepsOptionsTheUserAddedLater() throws {
        let connected = try text(ClaudeSettingsEditor.connect(original: Data(#"{"model":"opus"}"#.utf8), executablePath: exe))
        // The user adds padding to the status line Wiggleroom created.
        let edited = connected.replacingOccurrences(of: #""type": "command","#, with: #""type": "command", "padding": 2,"#)
        #expect(edited != connected)
        let out = try text(ClaudeSettingsEditor.disconnect(original: Data(edited.utf8)))
        let line = try #require((try json(out))["statusLine"] as? [String: Any])
        #expect(line["padding"] as? Int == 2)
        #expect(line["command"] as? String == "")
        #expect((try json(out))["model"] as? String == "opus")
    }

    @Test func compactOneLineFile() throws {
        let original = #"{"model":"opus"}"#
        let out = try text(ClaudeSettingsEditor.connect(original: Data(original.utf8), executablePath: exe))
        #expect((try json(out))["model"] as? String == "opus")
        #expect(try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8))) == original)
    }

    @Test func emptyAndBlankFiles() throws {
        for original in ["", "   \n", "{}", "{ }", "\u{FEFF}{}"] {
            let out = try text(ClaudeSettingsEditor.connect(original: Data(original.utf8), executablePath: exe))
            #expect(try command(out) == StatuslineCommand(executablePath: exe, previous: nil).commandLine)
            let back = try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8)))
            #expect(try json(back).isEmpty)
        }
    }

    @Test func commentsAndTrailingCommasArePreserved() throws {
        let original = """
        {
          // my model choice
          "model": "opus", /* inline */
          "env": {"A": "1",},
        }
        """
        let out = try text(ClaudeSettingsEditor.connect(original: Data(original.utf8), executablePath: exe))
        #expect(out.contains("// my model choice") && out.contains("/* inline */") && out.contains("{\"A\": \"1\",}"))
        #expect(ClaudeSettingsEditor.status(of: Data(out.utf8)) == .connected(StatuslineCommand(executablePath: exe, previous: nil)))
        #expect(try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8))) == original)
    }

    // MARK: Refusals: nothing is changed (lesson 7, fail safe)

    @Test func unparseableFilesAreLeftAlone() {
        for bad in ["{\"model\": ", "not json at all", "{\"a\": 1} trailing", "{\"a\": 'single'}", "{\"a\": tru}", "/* never closed {}"] {
            #expect(refusal(ClaudeSettingsEditor.connect(original: Data(bad.utf8), executablePath: exe)) != nil, "\(bad)")
            #expect(refusal(ClaudeSettingsEditor.disconnect(original: Data(bad.utf8))) != nil)
        }
        #expect(refusal(ClaudeSettingsEditor.connect(original: Data([0xFF, 0xFE, 0x00]), executablePath: exe)) == .notJSON("not UTF-8 text"))
        #expect(refusal(ClaudeSettingsEditor.connect(original: Data("[1,2]".utf8), executablePath: exe)) == .notAnObject)
    }

    @Test func unknownStatusLineShapesAreLeftAlone() {
        for bad in [#"{"statusLine": "echo hi"}"#,
                    #"{"statusLine": {"type": "text", "command": "x"}}"#,
                    #"{"statusLine": {"type": "command"}}"#,
                    #"{"statusLine": {"type": "command", "command": ["a"]}}"#,
                    #"{"statusLine": {"command": "x"}}"#] {
            #expect(refusal(ClaudeSettingsEditor.connect(original: Data(bad.utf8), executablePath: exe)) == .unknownStatusLine, "\(bad)")
        }
        let dup = #"{"statusLine": {"type": "command", "command": "a"}, "statusLine": {"type": "command", "command": "b"}}"#
        #expect(refusal(ClaudeSettingsEditor.connect(original: Data(dup.utf8), executablePath: exe)) == .duplicateStatusLine)
    }

    @Test func disconnectWhenNotConnected() {
        #expect(refusal(ClaudeSettingsEditor.disconnect(original: nil)) == .notConnected)
        #expect(refusal(ClaudeSettingsEditor.disconnect(original: Data(#"{"model":"x"}"#.utf8))) == .notConnected)
        #expect(refusal(ClaudeSettingsEditor.disconnect(original: Data(#"{"statusLine":{"type":"command","command":"echo hi"}}"#.utf8))) == .notConnected)
        // A Wiggleroom command with a damaged chain is not guessed at.
        let damaged = #"{"statusLine":{"type":"command","command":"'/x/wiggleroom-statusline' --then %%%"}}"#
        #expect(refusal(ClaudeSettingsEditor.disconnect(original: Data(damaged.utf8))) == .notConnected)
    }

    @Test func statusReporting() {
        #expect(ClaudeSettingsEditor.status(of: nil) == .noSettingsFile)
        #expect(ClaudeSettingsEditor.status(of: Data("{}".utf8)) == .notConnected(hasOtherStatusLine: false))
        #expect(ClaudeSettingsEditor.status(of: Data(#"{"statusLine":{"type":"command","command":"x"}}"#.utf8)) == .notConnected(hasOtherStatusLine: true))
        if case .unreadable = ClaudeSettingsEditor.status(of: Data("{".utf8)) {} else { Issue.record("expected unreadable") }
    }

    @Test func commandLineRoundTrips() throws {
        for prev in [nil, "echo hi", "printf '%s' \"$x\"\nsecond line", "emoji 🚀 and ünïcode"] {
            for path in [exe, exe2] {
                let c = StatuslineCommand(executablePath: path, previous: prev)
                #expect(StatuslineCommand.parse(c.commandLine) == c)
            }
        }
        #expect(StatuslineCommand.parse("/usr/local/bin/wiggleroom-statusline") != nil)
        #expect(StatuslineCommand.parse("echo wiggleroom-statusline") == nil)
        #expect(StatuslineCommand.parse("'/x/other-tool' --then ZWNobw==") == nil)
        #expect(StatuslineCommand.parse("'/x/wiggleroom-statusline' --then") == nil)
        #expect(StatuslineCommand.parse("'/x/wiggleroom-statusline") == nil)
        #expect(StatuslineCommand(executablePath: exe, previous: "   ").previous == nil)
    }

    // MARK: Files, on temp copies only

    @Test func applyOnTempFileBacksUpAndKeepsPermissions() throws {
        let home = makeTempHome()
        let paths = WiggleroomPaths(home: home)
        try FileManager.default.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
        try original.write(to: paths.claudeSettings)
        chmod(paths.claudeSettings.path, 0o644)
        let now = date(2027, 1, 14, 9, 5, tz: utc)
        let r = ClaudeSettingsEditor.apply(at: paths.claudeSettings, backupFolder: paths.backupFolder, now: now) { ClaudeSettingsEditor.connect(original: $0, executablePath: exe) }
        guard case .success(let (_, backup)) = r else { Issue.record("\(r)"); return }
        let b = try #require(backup)
        #expect(b.deletingLastPathComponent() == paths.backupFolder)
        #expect(SecureFile.permissions(of: paths.backupFolder) == 0o700)
        #expect(b.lastPathComponent.hasPrefix("settings.json.wiggleroom-backup-"))
        #expect(FileManager.default.contents(atPath: b.path) == original)
        #expect(SecureFile.permissions(of: b) == 0o600)
        #expect(SecureFile.permissions(of: paths.claudeSettings) == 0o644)
        let now2 = now.addingTimeInterval(0) // same second: backups must not overwrite each other
        _ = ClaudeSettingsEditor.apply(at: paths.claudeSettings, backupFolder: paths.backupFolder, now: now2) { ClaudeSettingsEditor.disconnect(original: $0) }
        #expect(FileManager.default.contents(atPath: paths.claudeSettings.path) == original)
        let names = try FileManager.default.contentsOfDirectory(atPath: paths.backupFolder.path)
        #expect(names.filter { $0.contains("wiggleroom-backup") }.count == 2)
        // Nothing is left next to the settings file.
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.claudeSettings.deletingLastPathComponent().path) == ["settings.json"])
    }

    @Test func applyCreatesAMissingFile() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        let r = ClaudeSettingsEditor.apply(at: paths.claudeSettings, backupFolder: paths.backupFolder) { ClaudeSettingsEditor.connect(original: $0, executablePath: exe) }
        guard case .success(let (_, backup)) = r else { Issue.record("\(r)"); return }
        #expect(backup == nil)
        let data = try #require(FileManager.default.contents(atPath: paths.claudeSettings.path))
        #expect(ClaudeSettingsEditor.status(of: data) == .connected(StatuslineCommand(executablePath: exe, previous: nil)))
    }

    @Test func unparseableFileOnDiskIsUntouched() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        try FileManager.default.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("{ \"model\": \"opus\", oops }".utf8)
        try bad.write(to: paths.claudeSettings)
        let r = ClaudeSettingsEditor.apply(at: paths.claudeSettings, backupFolder: paths.backupFolder) { ClaudeSettingsEditor.connect(original: $0, executablePath: exe) }
        if case .success = r { Issue.record("should have refused") }
        #expect(FileManager.default.contents(atPath: paths.claudeSettings.path) == bad)
        let names = try FileManager.default.contentsOfDirectory(atPath: paths.claudeSettings.deletingLastPathComponent().path)
        #expect(names == ["settings.json"]) // no backup, no temp file, nothing
    }

    @Test func fileChangedMeanwhileIsNotOverwritten() throws {
        let paths = WiggleroomPaths(home: makeTempHome())
        try FileManager.default.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.claudeSettings)
        let r = ClaudeSettingsEditor.apply(at: paths.claudeSettings, backupFolder: paths.backupFolder) { original in
            // Another program saves the file while Wiggleroom is preparing its change.
            try? Data(#"{"model":"changed"}"#.utf8).write(to: paths.claudeSettings)
            return ClaudeSettingsEditor.connect(original: original, executablePath: exe)
        }
        guard case .failure(.changedMeanwhile) = r else { Issue.record("\(r)"); return }
        #expect(FileManager.default.contents(atPath: paths.claudeSettings.path) == Data(#"{"model":"changed"}"#.utf8))
    }

    @Test func symlinkedSettingsFileStaysALink() throws {
        let home = makeTempHome()
        let paths = WiggleroomPaths(home: home)
        let dotfiles = home.appendingPathComponent("dotfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let real = dotfiles.appendingPathComponent("claude-settings.json")
        try Data(#"{"model":"opus"}"#.utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: paths.claudeSettings, withDestinationURL: real)
        let r = ClaudeSettingsEditor.apply(at: paths.claudeSettings, backupFolder: paths.backupFolder) { ClaudeSettingsEditor.connect(original: $0, executablePath: exe) }
        guard case .success = r else { Issue.record("\(r)"); return }
        // The backup (a full copy of the settings) never lands in the dotfiles folder.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dotfiles.path) == ["claude-settings.json"])
        let attrs = try FileManager.default.attributesOfItem(atPath: paths.claudeSettings.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        let data = try #require(FileManager.default.contents(atPath: real.path))
        if case .connected = ClaudeSettingsEditor.status(of: data) {} else { Issue.record("real file not connected") }
    }

    @Test func neverTouchesTheRealSettingsFile() {
        // Guard for this suite: every path used above is inside a temp folder.
        let tmp = makeTempHome()
        #expect(WiggleroomPaths(home: tmp).claudeSettings.path.hasPrefix(tmp.path))
        #expect(!WiggleroomPaths(home: tmp).claudeSettings.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"))
    }
}
