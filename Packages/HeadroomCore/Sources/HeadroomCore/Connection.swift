import Foundation

/// Connect and Disconnect as the app uses them: checks first, then the settings editor.
public struct Connection: Sendable {
    public var settingsURL: URL
    /// Where backups of the settings file go (Headroom's own private folder).
    public var backupFolder: URL
    /// The status line program inside the app, e.g. /Applications/Headroom.app/Contents/Helpers/headroom-statusline.
    public var executablePath: String

    public init(settingsURL: URL, backupFolder: URL, executablePath: String) {
        self.settingsURL = settingsURL
        self.backupFolder = backupFolder
        self.executablePath = executablePath
    }

    /// Why Headroom can't connect from where it is right now, or nil if it can.
    /// The setting stores this program's full path, so it must be a place that stays put.
    public static func locationProblem(executablePath: String, fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        if executablePath.contains("/AppTranslocation/") {
            return "macOS is running Headroom from a temporary copy because it was opened straight from the download. Move Headroom to your Applications folder, open it from there, then connect."
        }
        if executablePath.hasPrefix("/Volumes/") && executablePath.contains(".app/") {
            return "Headroom is running from a disk image or an external drive. Drag it to your Applications folder, open it from there, then connect."
        }
        if executablePath.contains("/.Trash/") {
            return "Headroom is in the Trash. Move it to your Applications folder first."
        }
        if !fileExists(executablePath) {
            return "Headroom's status line helper is missing from the app. Download Headroom again."
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

/// "Delete all Headroom data": the numbers file, its folder and the copy the widget reads.
/// Backups of Claude Code's settings are the user's own settings, so they are left alone.
public enum DataEraser {
    @discardableResult
    public static func eraseAll(paths: HeadroomPaths, appGroupFolder: URL?, extraFiles: [URL] = []) -> [String] {
        var problems: [String] = []
        let fm = FileManager.default
        var targets: [URL]
        if fm.fileExists(atPath: paths.backupFolder.path) {
            // Everything in Headroom's folder except the settings backups.
            let names = (try? fm.contentsOfDirectory(atPath: paths.supportFolder.path)) ?? []
            targets = names.filter { $0 != paths.backupFolder.lastPathComponent }.map { paths.supportFolder.appendingPathComponent($0) }
        } else {
            targets = [paths.supportFolder]
        }
        if let g = appGroupFolder { targets.append(g.appendingPathComponent(AppGroupFiles.snapshotName)) }
        targets += extraFiles
        for t in targets where fm.fileExists(atPath: t.path) || (try? fm.destinationOfSymbolicLink(atPath: t.path)) != nil {
            do { try fm.removeItem(at: t) } catch { problems.append("\(t.lastPathComponent): \(error.localizedDescription)") }
        }
        return problems
    }
}

/// Files in the App Group container shared by the app and the widget.
public enum AppGroupFiles {
    public static let snapshotName = "snapshot.json"
    public static let infoPlistKey = "HeadroomAppGroup"

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
