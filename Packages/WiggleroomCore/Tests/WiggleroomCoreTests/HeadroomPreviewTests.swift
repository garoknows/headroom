import Foundation
import Testing
@testable import WiggleroomCore

/// Wiggleroom was published for one day as an unsigned preview called Headroom. Anyone who tried
/// it and clicked Connect has a Headroom command in their status line setting. Wiggleroom takes
/// that place over and chains to the user's own status line underneath, never to the Headroom
/// helper. The Headroom commands below are written out by hand, exactly as the preview wrote them.
@Suite struct HeadroomPreviewTests {
    let exe = "/Applications/Wiggleroom.app/Contents/Helpers/wiggleroom-statusline"
    let headroomHelper = "/Applications/Headroom.app/Contents/Helpers/headroom-statusline"
    let mine = #"bash ~/.claude/statusline.sh "$HOME" | sed 's/a/b/' # it's mine"#

    /// The form the Headroom preview release wrote.
    func headroomCommand(_ helper: String, previous: String?) -> String {
        guard let previous else { return "[ -x '\(helper)' ] && exec '\(helper)' || true" }
        let b64 = Data(previous.utf8).base64EncodedString()
        return "[ -x '\(helper)' ] && exec '\(helper)' --then \(b64) || eval \"$(printf %s \(b64) | /usr/bin/base64 -D)\""
    }
    /// The plain form from before the preview release, which the preview still accepted.
    func plainHeadroomCommand(_ helper: String, previous: String?) -> String {
        guard let previous else { return "'\(helper)'" }
        return "'\(helper)' --then \(Data(previous.utf8).base64EncodedString())"
    }
    func settings(_ command: String, padding: Bool = true) -> Data {
        let pad = padding ? ",\n    \"padding\": 1" : ""
        return Data("{\n  \"model\": \"opus\",\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \(ClaudeSettingsEditor.jsonString(command))\(pad)\n  }\n}\n".utf8)
    }
    func text(_ r: Result<ClaudeSettingsEditor.Change, ClaudeSettingsEditor.Refusal>) throws -> String {
        switch r {
        case .success(let c): return String(decoding: c.newText, as: UTF8.self)
        case .failure(let f): Issue.record("refused: \(f)"); throw f
        }
    }
    func statusLine(_ s: String) throws -> [String: Any]? {
        (try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])?["statusLine"] as? [String: Any]
    }

    @Test func headroomCommandWithAPreviousCommandIsUnwrapped() throws {
        for original in [headroomCommand(headroomHelper, previous: mine), plainHeadroomCommand(headroomHelper, previous: mine)] {
            let out = try text(ClaudeSettingsEditor.connect(original: settings(original), executablePath: exe))
            #expect(!out.contains("headroom-statusline"), "still chains to Headroom: \(out)")
            let line = try #require(try statusLine(out))
            let cmd = try #require(line["command"] as? String)
            #expect(StatuslineCommand.parse(cmd) == StatuslineCommand(executablePath: exe, previous: mine))
            #expect(line["padding"] as? Int == 1)
            // Disconnect gives the user's own status line back, not the Headroom one.
            let back = try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8)))
            #expect(try statusLine(back)?["command"] as? String == mine)
            #expect(try statusLine(back)?["padding"] as? Int == 1)
        }
    }

    @Test func headroomCommandWithoutAPreviousCommand() throws {
        for original in [headroomCommand(headroomHelper, previous: nil), plainHeadroomCommand(headroomHelper, previous: nil)] {
            let out = try text(ClaudeSettingsEditor.connect(original: settings(original, padding: false), executablePath: exe))
            #expect(!out.contains("headroom-statusline"), "still chains to Headroom: \(out)")
            let cmd = try #require(try statusLine(out)?["command"] as? String)
            #expect(StatuslineCommand.parse(cmd) == StatuslineCommand(executablePath: exe, previous: nil))
            // Disconnect leaves no status line, as before the user tried Headroom.
            let back = try text(ClaudeSettingsEditor.disconnect(original: Data(out.utf8)))
            #expect(try statusLine(back) == nil)
            #expect(back.contains("\"model\": \"opus\""))
        }
    }

    /// The user deleted Headroom without clicking Disconnect. Connect works on the real file
    /// (in a temp home) and still unwraps the command.
    @Test func headroomAppAlreadyDeleted() throws {
        let home = makeTempHome()
        let paths = WiggleroomPaths(home: home)
        let goneHelper = home.appendingPathComponent(".Trash/Headroom.app/Contents/Helpers/headroom-statusline").path
        #expect(!FileManager.default.fileExists(atPath: goneHelper))
        let helper = home.appendingPathComponent("Wiggleroom.app/Contents/Helpers/wiggleroom-statusline")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        chmod(helper.path, 0o755)
        try FileManager.default.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        for previous in [mine, nil] {
            try settings(headroomCommand(goneHelper, previous: previous)).write(to: paths.claudeSettings)
            let c = Connection(settingsURL: paths.claudeSettings, backupFolder: paths.backupFolder, executablePath: helper.path)
            guard case .done = c.connect() else { Issue.record("connect refused"); return }
            #expect(c.status() == .connected(StatuslineCommand(executablePath: helper.path, previous: previous)))
            let saved = try String(contentsOf: paths.claudeSettings, encoding: .utf8)
            #expect(!saved.contains("headroom-statusline"))
        }
    }

    @Test func nestedAndLeftoverHeadroomCommandsAreFullyUnwrapped() throws {
        // Headroom wrapped around Headroom (connected from two places).
        let inner = headroomCommand("/Applications/Old Apps/Headroom.app/Contents/Helpers/headroom-statusline", previous: mine)
        #expect(StatuslineCommand.unwrappingHeadroomPreview(headroomCommand(headroomHelper, previous: inner)) == mine)
        #expect(StatuslineCommand.unwrappingHeadroomPreview(headroomCommand(headroomHelper, previous: headroomCommand(headroomHelper, previous: nil))) == nil)
        // A Wiggleroom setting that somehow has Headroom underneath it is cleaned up on Connect.
        let mixed = StatuslineCommand(executablePath: exe, previous: headroomCommand(headroomHelper, previous: mine)).commandLine
        let out = try text(ClaudeSettingsEditor.connect(original: settings(mixed), executablePath: exe))
        #expect(!out.contains("headroom-statusline"))
        #expect(StatuslineCommand.parse(try #require(try statusLine(out)?["command"] as? String))?.previous == mine)
        // Plain user commands pass through untouched.
        #expect(StatuslineCommand.unwrappingHeadroomPreview(mine) == mine)
        #expect(StatuslineCommand.unwrappingHeadroomPreview(nil) == nil)
    }

    @Test func onlyTheExactHeadroomFormsAreRecognized() {
        #expect(StatuslineCommand.parseHeadroomPreview(headroomCommand(headroomHelper, previous: mine))?.previous == mine)
        #expect(StatuslineCommand.parseHeadroomPreview(headroomCommand(headroomHelper, previous: nil)) != nil)
        #expect(StatuslineCommand.parseHeadroomPreview(plainHeadroomCommand(headroomHelper, previous: mine))?.previous == mine)
        // Not Headroom's: someone else's tool with a similar name, a relative path, extra text,
        // a broken --then, or Wiggleroom's own command.
        #expect(StatuslineCommand.parseHeadroomPreview("echo headroom-statusline") == nil)
        #expect(StatuslineCommand.parseHeadroomPreview("headroom-statusline") == nil)
        #expect(StatuslineCommand.parseHeadroomPreview("'/x/headroom' --then ZWNobw==") == nil)
        #expect(StatuslineCommand.parseHeadroomPreview(headroomCommand(headroomHelper, previous: mine) + "; echo extra") == nil)
        #expect(StatuslineCommand.parseHeadroomPreview("'\(headroomHelper)' --then !!") == nil)
        #expect(StatuslineCommand.parseHeadroomPreview(StatuslineCommand(executablePath: exe, previous: mine).commandLine) == nil)
        // And Wiggleroom never mistakes a Headroom command for its own.
        #expect(StatuslineCommand.parse(headroomCommand(headroomHelper, previous: mine)) == nil)
        // A command that only looks like Headroom's is chained as the user's own, unchanged.
        let lookalike = "echo headroom-statusline"
        #expect(StatuslineCommand.unwrappingHeadroomPreview(lookalike) == lookalike)
    }

    /// "Delete all Wiggleroom data" also clears the Headroom preview's folder, keeping only the
    /// settings backups, and never touches the unrelated Headroom app's folder.
    @Test func eraseAlsoClearsTheHeadroomPreviewFolder() throws {
        for withBackups in [true, false] {
            let home = makeTempHome()
            let paths = WiggleroomPaths(home: home)
            let old = paths.headroomPreviewFolder
            try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: old.appendingPathComponent("usage.json"))
            try Data("{}".utf8).write(to: old.appendingPathComponent("settings.json"))
            let oldBackup = old.appendingPathComponent("settings-backups/settings.json.backup-1")
            if withBackups {
                try FileManager.default.createDirectory(at: oldBackup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{}".utf8).write(to: oldBackup)
            }
            let otherApp = home.appendingPathComponent("Library/Application Support/Headroom/keep.json")
            try FileManager.default.createDirectory(at: otherApp.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: otherApp)

            let problems = DataEraser.eraseAll(paths: paths, appGroupFolder: nil)
            #expect(problems.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent("usage.json").path))
            #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent("settings.json").path))
            #expect(FileManager.default.fileExists(atPath: oldBackup.path) == withBackups)
            #expect(FileManager.default.fileExists(atPath: old.path) == withBackups)
            #expect(FileManager.default.fileExists(atPath: otherApp.path))
        }
        #expect(WiggleroomPaths.headroomPreviewFolderName == "io.github.garoknows.headroom")
    }
}
