import Darwin
import Foundation

/// Connects Headroom to Claude Code by editing the `statusLine` setting in `~/.claude/settings.json`,
/// and puts it back on Disconnect. Only ever runs when the user clicks a button.
///
/// Safety rules (PRD section 7, lessons 7 and 8):
/// - Only the `statusLine` part of the file changes; every other byte stays as the user wrote it.
/// - A timestamped backup is written first.
/// - The new text is read back and checked before it replaces the file, and a file that was
///   valid JSON stays valid JSON.
/// - If the file can't be understood, nothing is changed and the reason is returned.
/// - The file is read again right before writing; if it changed meanwhile, nothing is written.
public enum ClaudeSettingsEditor {

    public enum Refusal: Error, Equatable, Sendable {
        case unreadableFile(String)
        case notJSON(String)
        case notAnObject
        case duplicateStatusLine
        case unknownStatusLine
        case notConnected
        case changedMeanwhile
        case checkFailed(String)
        case writeFailed(String)

        /// Plain-English explanation for the Settings window.
        public var message: String {
            switch self {
            case .unreadableFile(let why): "Headroom couldn't read your Claude Code settings file (\(why)). Nothing was changed."
            case .notJSON(let why): "Your Claude Code settings file isn't valid JSON (\(why)), so Headroom left it exactly as it is. Fix the file, then try again."
            case .notAnObject: "Your Claude Code settings file doesn't have the expected layout, so Headroom left it exactly as it is."
            case .duplicateStatusLine: "Your Claude Code settings file lists \"statusLine\" more than once, so Headroom left it exactly as it is."
            case .unknownStatusLine: "Your status line setting is in a form Headroom doesn't recognize, so Headroom left it exactly as it is."
            case .notConnected: "Headroom isn't in your status line setting (it may have been changed since you connected). Nothing was changed."
            case .changedMeanwhile: "Your Claude Code settings changed while Headroom was working on them. Nothing was changed. Please try again."
            case .checkFailed(let why): "Headroom's safety check stopped the change (\(why)). Nothing was changed."
            case .writeFailed(let why): "Headroom couldn't save your Claude Code settings (\(why)). Nothing was changed."
            }
        }
    }

    public enum Status: Equatable, Sendable {
        case noSettingsFile
        case notConnected(hasOtherStatusLine: Bool)
        case connected(StatuslineCommand)
        case unreadable(Refusal)
    }

    public struct Change: Equatable, Sendable {
        public var newText: Data
        public var summary: String
    }

    // MARK: Reading the current state

    public static func status(of original: Data?) -> Status {
        guard let original else { return .noSettingsFile }
        switch inspect(original) {
        case .failure(let r): return .unreadable(r)
        case .success(let doc):
            guard let line = doc.statusLine else { return .notConnected(hasOtherStatusLine: false) }
            if let cmd = line.command.flatMap(StatuslineCommand.parse) { return .connected(cmd) }
            return .notConnected(hasOtherStatusLine: true)
        }
    }

    // MARK: Pure text changes (tested directly)

    /// The new file text that connects Headroom, or why it can't be done.
    /// `original` is nil when there is no settings file yet.
    public static func connect(original: Data?, executablePath: String) -> Result<Change, Refusal> {
        let text = original ?? Data()
        if isBlank(text) {
            let cmd = StatuslineCommand(executablePath: executablePath, previous: nil)
            let new = "{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \(jsonString(cmd.commandLine))\n  }\n}\n"
            return verify(original: nil, new: Data(new.utf8), expectedCommand: cmd.commandLine,
                          summary: "Connected. Claude Code had no status line before.")
        }
        let doc: Document
        switch inspect(text) { case .failure(let r): return .failure(r); case .success(let d): doc = d }
        let bytes = [UInt8](text)

        if let line = doc.statusLine {
            guard let cmdNode = line.commandNode, let current = line.command else { return .failure(.unknownStatusLine) }
            let new: StatuslineCommand
            let summary: String
            if let existing = StatuslineCommand.parse(current) {
                if existing.executablePath == executablePath {
                    return .success(Change(newText: text, summary: "Already connected."))
                }
                new = StatuslineCommand(executablePath: executablePath, previous: existing.previous)
                summary = "Connection updated to where Headroom is now."
            } else {
                new = StatuslineCommand(executablePath: executablePath, previous: current)
                summary = "Connected. Your existing status line keeps working; Headroom runs it after saving the numbers."
            }
            var out = bytes
            out.replaceSubrange(cmdNode.range, with: Array(jsonString(new.commandLine).utf8))
            return verify(original: text, new: Data(out), expectedCommand: new.commandLine, summary: summary)
        }

        // No statusLine yet: add one as the first member of the top-level object.
        let cmd = StatuslineCommand(executablePath: executablePath, previous: nil)
        let obj = doc.root
        let open = obj.range.lowerBound
        var insert: String
        if let first = obj.members.first {
            if let indent = lineIndent(bytes, before: first.keyRange.lowerBound, after: open) {
                let inner = indent + (indent.contains("\t") ? "\t" : "  ")
                insert = "\n\(indent)\"statusLine\": {\n\(inner)\"type\": \"command\",\n\(inner)\"command\": \(jsonString(cmd.commandLine))\n\(indent)},"
            } else {
                insert = "\"statusLine\": {\"type\": \"command\", \"command\": \(jsonString(cmd.commandLine))}, "
            }
        } else {
            insert = "\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \(jsonString(cmd.commandLine))\n  }\n"
        }
        var out = bytes
        out.insert(contentsOf: Array(insert.utf8), at: open + 1)
        return verify(original: text, new: Data(out), expectedCommand: cmd.commandLine,
                      summary: "Connected. Claude Code had no status line before.")
    }

    /// The new file text that disconnects Headroom and puts the previous status line back.
    public static func disconnect(original: Data?) -> Result<Change, Refusal> {
        guard let original, !isBlank(original) else { return .failure(.notConnected) }
        let doc: Document
        switch inspect(original) { case .failure(let r): return .failure(r); case .success(let d): doc = d }
        guard let line = doc.statusLine, let cmdNode = line.commandNode, let current = line.command,
              let ours = StatuslineCommand.parse(current) else { return .failure(.notConnected) }
        var out = [UInt8](original)
        if let previous = ours.previous {
            out.replaceSubrange(cmdNode.range, with: Array(jsonString(previous).utf8))
            return verify(original: original, new: Data(out), expectedCommand: previous,
                          summary: "Disconnected. Your previous status line is back.")
        }
        // Headroom added the statusLine setting. If the user has since added options to it (like
        // padding), keep them and only empty the command; otherwise remove the whole setting.
        if line.node.members.contains(where: { $0.key != "type" && $0.key != "command" }) {
            out.replaceSubrange(cmdNode.range, with: Array("\"\"".utf8))
            return verify(original: original, new: Data(out), expectedCommand: "",
                          summary: "Disconnected. Your status line options are kept, with no command.")
        }
        let members = doc.root.members
        guard let idx = members.firstIndex(where: { $0.key == "statusLine" }) else { return .failure(.notConnected) }
        let m = members[idx]
        let range: Range<Int>
        if idx + 1 < members.count {
            // Undo exactly what connect inserted: the line break and indent before the key,
            // through the comma after the value (and the space after it on a one-line file).
            var s = m.keyRange.lowerBound
            while s > 0 && (out[s - 1] == 0x20 || out[s - 1] == 0x09) { s -= 1 }
            let ownLine = s > 0 && out[s - 1] == 0x0A
            if ownLine { s -= 1 } else { s = m.keyRange.lowerBound }
            var e = m.value.range.upperBound
            while e < out.count && (out[e] == 0x20 || out[e] == 0x09) { e += 1 }
            guard e < out.count, out[e] == 0x2C else { return .failure(.checkFailed("unexpected layout around the status line")) }
            e += 1
            if !ownLine { while e < out.count && out[e] == 0x20 { e += 1 } }
            range = s..<e
        } else if idx > 0 {
            range = members[idx - 1].value.range.upperBound..<m.value.range.upperBound
        } else {
            range = (doc.root.range.lowerBound + 1)..<(doc.root.range.upperBound - 1)
        }
        if idx == 0 && members.count == 1 {
            out.replaceSubrange(range, with: Array("\n".utf8))
        } else {
            out.removeSubrange(range)
        }
        return verify(original: original, new: Data(out), expectedCommand: nil,
                      summary: "Disconnected. Claude Code has no status line again, as before.")
    }

    // MARK: Files (the only part that touches the disk)

    /// Connects or disconnects on the real file at `url`: backup, re-check, atomic replace.
    /// Backups go into `backupFolder` (Headroom's own private folder), never next to the file:
    /// a settings file linked into a dotfiles repository must not get a full copy (which can hold
    /// API keys in "env") dropped beside it, where a later commit could publish it.
    /// Returns the change made and the backup's location.
    public static func apply(at url: URL, backupFolder: URL, now: Date = Date(),
                             _ transform: (Data?) -> Result<Change, Refusal>) -> Result<(Change, URL?), Refusal> {
        let target = resolvedTarget(url)
        let before: Data?
        switch readSettings(target) { case .failure(let r): return .failure(r); case .success(let d): before = d }
        let change: Change
        switch transform(before) { case .failure(let r): return .failure(r); case .success(let c): change = c }
        if let before, change.newText == before { return .success((change, nil)) }

        var backup: URL?
        do {
            let dir = target.deletingLastPathComponent()
            if before == nil {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            if let before {
                try SecureFile.ensurePrivateFolder(backupFolder)
                let b = backupURL(in: backupFolder, now: now)
                try SecureFile.atomicWrite(before, to: b, mode: 0o600)
                backup = b
            }
            // Lesson 8: look again right before the risky step.
            switch readSettings(target) {
            case .failure(let r): return .failure(r)
            case .success(let again): if again != before { return .failure(.changedMeanwhile) }
            }
            let mode = SecureFile.permissions(of: target) ?? 0o600
            try SecureFile.atomicWrite(change.newText, to: target, mode: mode)
        } catch {
            return .failure(.writeFailed(String(describing: error)))
        }
        return .success((change, backup))
    }

    public static func readSettings(_ url: URL) -> Result<Data?, Refusal> {
        var st = stat()
        if lstat(url.path, &st) != 0 {
            return errno == ENOENT ? .success(nil) : .failure(.unreadableFile(String(cString: strerror(errno))))
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return .failure(.unreadableFile("it isn't a regular file")) }
        guard st.st_size <= 5_000_000 else { return .failure(.unreadableFile("it's unusually large")) }
        guard let data = FileManager.default.contents(atPath: url.path) else { return .failure(.unreadableFile("permission denied")) }
        return .success(data)
    }

    /// People who keep settings in a dotfiles folder often link settings.json there. Headroom
    /// edits the real file and leaves the link in place.
    static func resolvedTarget(_ url: URL) -> URL {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK else { return url }
        return url.resolvingSymlinksInPath()
    }

    static func backupURL(in dir: URL, now: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: now)
        var candidate = dir.appendingPathComponent("settings.json.headroom-backup-\(stamp)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("settings.json.headroom-backup-\(stamp)-\(n)")
            n += 1
        }
        return candidate
    }

    // MARK: Internals

    struct StatusLineInfo {
        var node: JSONSourceScanner.Node
        var commandNode: JSONSourceScanner.Node?
        var command: String?
    }

    struct Document {
        var root: JSONSourceScanner.Node
        var statusLine: StatusLineInfo?
        var strict: Bool
    }

    static func inspect(_ data: Data) -> Result<Document, Refusal> {
        guard String(data: data, encoding: .utf8) != nil else { return .failure(.notJSON("not UTF-8 text")) }
        let parsed: (JSONSourceScanner.Node, JSONSourceScanner)
        switch JSONSourceScanner.parse([UInt8](data)) {
        case .failure(let f): return .failure(.notJSON("\(f.reason) at byte \(f.offset)"))
        case .success(let p): parsed = p
        }
        let root = parsed.0
        guard root.kind == .object else { return .failure(.notAnObject) }
        let lines = root.members.filter { $0.key == "statusLine" }
        guard lines.count <= 1 else { return .failure(.duplicateStatusLine) }
        var info: StatusLineInfo?
        if let line = lines.first {
            guard line.value.kind == .object else { return .failure(.unknownStatusLine) }
            let typeNodes = line.value.members.filter { $0.key == "type" }
            let cmdNodes = line.value.members.filter { $0.key == "command" }
            guard typeNodes.count == 1, typeNodes[0].value.string == "command",
                  cmdNodes.count == 1, cmdNodes[0].value.kind == .string else { return .failure(.unknownStatusLine) }
            info = StatusLineInfo(node: line.value, commandNode: cmdNodes[0].value, command: cmdNodes[0].value.string)
        }
        let strict = (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
        return .success(Document(root: root, statusLine: info, strict: strict))
    }

    /// The new text must parse, keep every other setting byte-for-byte, carry exactly the
    /// intended command, and stay strict JSON if the original was.
    static func verify(original: Data?, new: Data, expectedCommand: String?, summary: String) -> Result<Change, Refusal> {
        guard case .success(let after) = inspect(new) else { return .failure(.checkFailed("the new text didn't read back")) }
        if let expectedCommand {
            guard after.statusLine?.command == expectedCommand,
                  after.statusLine?.node.members.first(where: { $0.key == "type" })?.value.string == "command" else {
                return .failure(.checkFailed("the status line didn't read back as expected"))
            }
        } else {
            guard after.statusLine == nil else { return .failure(.checkFailed("the status line is still there")) }
        }
        if let original, case .success(let before) = inspect(original) {
            if before.strict && !after.strict { return .failure(.checkFailed("the result wasn't valid JSON")) }
            let a = otherMembers(before, [UInt8](original))
            let b = otherMembers(after, [UInt8](new))
            guard a == b else { return .failure(.checkFailed("another setting would have changed")) }
            // Other parts of the statusLine object (like padding) must survive too.
            if let bl = before.statusLine, let al = after.statusLine {
                guard statusLineExtras(bl, [UInt8](original)) == statusLineExtras(al, [UInt8](new)) else {
                    return .failure(.checkFailed("a status line option would have changed"))
                }
            }
        } else if (try? JSONSerialization.jsonObject(with: new, options: [])) == nil {
            return .failure(.checkFailed("the result wasn't valid JSON"))
        }
        return .success(Change(newText: new, summary: summary))
    }

    /// Every top-level setting except statusLine, as (key, exact source text of its value).
    static func otherMembers(_ doc: Document, _ bytes: [UInt8]) -> [[String]] {
        doc.root.members.filter { $0.key != "statusLine" }.map { [$0.key, String(decoding: bytes[$0.value.range], as: UTF8.self)] }
    }

    static func statusLineExtras(_ line: StatusLineInfo, _ bytes: [UInt8]) -> [[String]] {
        line.node.members.filter { $0.key != "command" }.map { [$0.key, String(decoding: bytes[$0.value.range], as: UTF8.self)] }
    }

    static func isBlank(_ d: Data) -> Bool {
        var bytes = [UInt8](d)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        return bytes.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
    }

    /// The whitespace that starts the line `pos` is on, if that line begins after `after`.
    static func lineIndent(_ b: [UInt8], before pos: Int, after: Int) -> String? {
        var s = pos
        while s > 0 && b[s - 1] != 0x0A { s -= 1 }
        guard s > after else { return nil }
        let ws = b[s..<pos]
        guard ws.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) else { return nil }
        return String(decoding: ws, as: UTF8.self)
    }

    static func jsonString(_ s: String) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: (try? e.encode(s)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
