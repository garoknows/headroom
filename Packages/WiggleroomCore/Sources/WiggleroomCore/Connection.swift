import Foundation

/// Connect and Disconnect as the app uses them: checks first, then the settings editor.
public struct Connection: Sendable {
    public var settingsURL: URL
    /// Where backups of the settings file go (Wiggleroom's own private folder).
    public var backupFolder: URL
    /// The status line program inside the app, e.g. /Applications/Wiggleroom.app/Contents/Helpers/wiggleroom-statusline.
    public var executablePath: String

    public init(settingsURL: URL, backupFolder: URL, executablePath: String) {
        self.settingsURL = settingsURL
        self.backupFolder = backupFolder
        self.executablePath = executablePath
    }

    /// Why Wiggleroom can't connect from where it is right now, or nil if it can.
    /// The setting stores this program's full path, so it must be a place that stays put.
    public static func locationProblem(executablePath: String, fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        if executablePath.contains("/AppTranslocation/") {
            return "macOS is running Wiggleroom from a temporary copy because it was opened straight from the download. Move Wiggleroom to your Applications folder, open it from there, then connect."
        }
        if executablePath.hasPrefix("/Volumes/") && executablePath.contains(".app/") {
            return "Wiggleroom is running from a disk image or an external drive. Drag it to your Applications folder, open it from there, then connect."
        }
        if executablePath.contains("/.Trash/") {
            return "Wiggleroom is in the Trash. Move it to your Applications folder first."
        }
        if !fileExists(executablePath) {
            return "Wiggleroom's status line helper is missing from the app. Download Wiggleroom again."
        }
        return nil
    }

    public func status() -> ClaudeSettingsEditor.Status {
        switch ClaudeSettingsEditor.readSettings(ClaudeSettingsEditor.resolvedTarget(settingsURL)) {
        case .failure(let r): return .unreadable(r)
        case .success(let d): return ClaudeSettingsEditor.status(of: d)
        }
    }

    public enum Outcome: Equatable, Sendable {
        case done(summary: String, backup: URL?)
        case refused(String)
    }

    public func connect(now: Date = Date()) -> Outcome {
        // Lesson 8: the location and the program are checked at the moment of the click.
        if let problem = Self.locationProblem(executablePath: executablePath) { return .refused(problem) }
        let path = executablePath
        switch ClaudeSettingsEditor.apply(at: settingsURL, backupFolder: backupFolder, now: now, { ClaudeSettingsEditor.connect(original: $0, executablePath: path) }) {
        case .success(let (change, backup)): return .done(summary: change.summary, backup: backup)
        case .failure(let r): return .refused(r.message)
        }
    }

    public func disconnect(now: Date = Date()) -> Outcome {
        switch ClaudeSettingsEditor.apply(at: settingsURL, backupFolder: backupFolder, now: now, { ClaudeSettingsEditor.disconnect(original: $0) }) {
        case .success(let (change, backup)): return .done(summary: change.summary, backup: backup)
        case .failure(let r): return .refused(r.message)
        }
    }
}

/// "Delete all Wiggleroom data": the numbers file, its folder and the copy the widget reads.
/// Backups of Claude Code's settings are the user's own settings, so they are left alone.
public enum DataEraser {
    @discardableResult
    public static func eraseAll(paths: WiggleroomPaths, appGroupFolder: URL?, extraFiles: [URL] = []) -> [String] {
        var problems: [String] = []
        let fm = FileManager.default
        // Wiggleroom's own folder, and the Headroom preview's folder from before the rename, by the
        // same rule. Never "Application Support/Headroom", which belongs to an unrelated app.
        var targets = contents(of: paths.supportFolder, keeping: paths.backupFolder.lastPathComponent)
            + contents(of: paths.headroomPreviewFolder, keeping: paths.backupFolder.lastPathComponent)
        if let g = appGroupFolder { targets.append(g.appendingPathComponent(AppGroupFiles.snapshotName)) }
        targets += extraFiles
        for t in targets where fm.fileExists(atPath: t.path) || (try? fm.destinationOfSymbolicLink(atPath: t.path)) != nil {
            do { try fm.removeItem(at: t) } catch { problems.append("\(t.lastPathComponent): \(error.localizedDescription)") }
        }
        return problems
    }

    /// What to remove from `folder`: everything except its `keep` subfolder (the settings
    /// backups) if that exists, otherwise the whole folder.
    static func contents(of folder: URL, keeping keep: String) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent(keep).path) else { return [folder] }
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0 != keep }.map { folder.appendingPathComponent($0) }
    }
}

/// Files in the App Group container shared by the app and the widget.
public enum AppGroupFiles {
    /// 0.1's file: Claude Code only. Still written during 0.2.x so a downgrade keeps working.
    public static let snapshotName = "snapshot.json"
    /// 0.2's file: one snapshot per connected tool.
    public static let toolsName = "snapshots.json"
    public static let infoPlistKey = "WiggleroomAppGroup"

    /// The group name from the app's or widget's Info.plist, or nil in builds without one
    /// (unsigned builds have no App Group).
    public static func groupIdentifier(bundle: Bundle = .main) -> String? {
        guard let id = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
    }

    public static func folder(bundle: Bundle = .main) -> URL? {
        guard let id = groupIdentifier(bundle: bundle) else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// The snapshot the widget shows, if it's there and sane.
    public static func readSnapshot(in folder: URL, now: Date = Date()) -> UsageSnapshot? {
        guard let s = SecureFile.readSmallFile(folder.appendingPathComponent(snapshotName)).flatMap(UsageSnapshot.decode),
              SnapshotPolicy.isPlausible(s, now: now) else { return nil }
        return s
    }

    /// Every tool's numbers the widget can show. Reads 0.2's per-tool file; if there isn't one
    /// yet (the app hasn't run since the upgrade), reads 0.1's file as Claude Code, so widgets
    /// placed before the upgrade keep showing their numbers. Implausible entries are dropped.
    public static func readTools(in folder: URL, now: Date = Date()) -> [ToolSnapshot] {
        if let f = SecureFile.readSmallFile(folder.appendingPathComponent(toolsName)).flatMap(ToolsFile.decode) {
            return f.tools.filter { SnapshotPolicy.isPlausible($0.usage, now: now) }
        }
        // Upgraded from 0.1 and the 0.2 app hasn't written its file yet.
        return readSnapshot(in: folder, now: now).map { [ToolSnapshot(tool: .claudeCode, usage: $0)] } ?? []
    }

    /// Writes 0.2's per-tool file (only if it changed) and keeps 0.1's file up to date for
    /// Claude Code. Each tool follows the same rule as 0.1: never replace good numbers with bad
    /// or older ones. A tool missing from `tools` is removed (it was disconnected).
    /// Returns true if anything changed, so the widget should reload.
    @discardableResult
    public static func publishTools(_ tools: [ToolSnapshot], to folder: URL, now: Date = Date()) -> Bool {
        let current = SecureFile.readSmallFile(folder.appendingPathComponent(toolsName)).flatMap(ToolsFile.decode)
        var out: [ToolSnapshot] = []
        for tool in Tool.allCases {
            let have = current?.usage(tool)
            let candidate = tools.first { $0.tool == tool }?.usage
            guard candidate != nil else { continue }   // not connected: leave it out
            if SnapshotPolicy.shouldReplace(current: have, with: candidate, now: now), let candidate {
                out.append(ToolSnapshot(tool: tool, usage: candidate))
            } else if let have, SnapshotPolicy.isPlausible(have, now: now) {
                out.append(ToolSnapshot(tool: tool, usage: have))
            }
        }
        var changed = false
        let file = ToolsFile(tools: out)
        if file != current, let data = try? file.encoded() {
            do {
                try SecureFile.atomicWrite(data, to: folder.appendingPathComponent(toolsName), mode: 0o600)
                changed = true
            } catch {}
        }
        // 0.1's file, for Claude Code only (downgrade safety).
        if publish(tools.first { $0.tool == .claudeCode }?.usage, to: folder, now: now) { changed = true }
        return changed
    }

    /// Copies `candidate` into the group folder if it's good and newer (lesson 12).
    /// Returns true if the file changed (so the widget should reload).
    @discardableResult
    public static func publish(_ candidate: UsageSnapshot?, to folder: URL, now: Date = Date()) -> Bool {
        let current = SecureFile.readSmallFile(folder.appendingPathComponent(snapshotName)).flatMap(UsageSnapshot.decode)
        guard SnapshotPolicy.shouldReplace(current: current, with: candidate, now: now), let candidate,
              let data = try? candidate.encoded() else { return false }
        do {
            try SecureFile.atomicWrite(data, to: folder.appendingPathComponent(snapshotName), mode: 0o600)
            return true
        } catch {
            return false
        }
    }
}
