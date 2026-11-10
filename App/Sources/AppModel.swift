import AppKit
import Combine
import WiggleroomCore
import WiggleroomUI
import WiggleroomWindows
import ServiceManagement
import UserNotifications
import WidgetKit

/// Everything the app's windows and menu show, and every action they can take.
@MainActor
final class AppModel: WindowModel {
    let paths = WiggleroomPaths.currentUser()
    /// The App Group folder shared with the widget. Nil in unsigned builds.
    let groupFolder = AppGroupFiles.folder()
    let defaults = UserDefaults.standard

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var watcherState: UsageWatcher.State = .starting
    @Published private(set) var connection: ClaudeSettingsEditor.Status = .noSettingsFile
    @Published var lastMessage: String?
    @Published var lastBackup: URL?
    @Published private(set) var now = Date()
    @Published private(set) var notificationsAllowed: Bool?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    @Published var showMenuBar: Bool { didSet { defaults.set(showMenuBar, forKey: Keys.menuBar); onMenuBarChange?(showMenuBar) } }
    @Published var menuBarChoice: MenuBarChoice { didSet { defaults.set(menuBarChoice.rawValue, forKey: Keys.menuBarChoice) } }

    // Codex (0.2). Connecting is only an opt-in: nothing in Codex changes.
    @Published private(set) var codexConnected: Bool
    @Published private(set) var codexStatus: CodexStatus = .noSessions
    @Published private(set) var codexSnapshot: UsageSnapshot?
    @Published private(set) var codexWatcherState: CodexWatcher.State = .stopped
    let codexPaths = CodexPaths(home: WiggleroomPaths.currentUser().home)
    private var codexWatcher: CodexWatcher?
    @Published var alerts: AlertSettings { didSet { saveAlerts() } }

    var onMenuBarChange: ((Bool) -> Void)?
    private var watcher: UsageWatcher?
    private var clock: Timer?

    enum Keys {
        static let menuBar = "showMenuBar"
        static let alerts = "alertSettings"
        static let alertRecord = "alertRecord"
        static let setupDone = "setupDone"
        static let menuBarChoice = "menuBarShows"
        static let codexConnected = "codexConnected"
    }

    init() {
        showMenuBar = defaults.bool(forKey: Keys.menuBar)   // off by default (PRD section 5)
        menuBarChoice = defaults.string(forKey: Keys.menuBarChoice).flatMap(MenuBarChoice.init(rawValue:)) ?? .default
        codexConnected = defaults.bool(forKey: Keys.codexConnected)   // off until the user connects
        if let d = defaults.data(forKey: Keys.alerts), let a = try? JSONDecoder().decode(AlertSettings.self, from: d) {
            alerts = a
        } else {
            alerts = .default
        }
    }

    var setupDone: Bool {
        get { defaults.bool(forKey: Keys.setupDone) }
        set { defaults.set(newValue, forKey: Keys.setupDone) }
    }

    var connectionHelper: Connection { Connection(settingsURL: paths.claudeSettings, backupFolder: paths.backupFolder, executablePath: HelperLocation.executablePath) }

    func start() {
        let w = UsageWatcher(folder: paths.supportFolder)
        w.onChange = { [weak self] in self?.refresh() }
        w.onState = { [weak self] s in self?.watcherState = s }
        watcher = w
        w.start()
        watcherState = w.state
        refreshConnection()
        if codexConnected {
            codexSnapshot = CodexStore.load(paths: paths)
            startCodexWatcher()
        }
        refresh()
        refreshCodex()
        refreshNotificationPermission()
        // Once a minute: "As of" turns amber, bars dim, resets pass. Cheap: nothing is read from disk.
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }

    // MARK: Numbers

    /// Reads the status line program's file, keeps the best good data, hands it to the widget.
    func refresh() {
        now = Date()
        // Temp files a cancelled status line run left behind.
        SecureFile.removeStaleTempFiles(in: paths.supportFolder, olderThan: 60)
        let fromScript = SecureFile.readSmallFile(paths.usageFile).flatMap(UsageSnapshot.decode)
        let fromGroup = groupFolder.flatMap { AppGroupFiles.readSnapshot(in: $0, now: now) }
        // Never replace good data with bad or older data (lesson 12).
        var best = snapshot ?? fromGroup
        if SnapshotPolicy.shouldReplace(current: best, with: fromScript, now: now) { best = fromScript }
        if let best, !SnapshotPolicy.isPlausible(best, now: now) { return }
        if best != snapshot { snapshot = best }
        publishToWidget()
        evaluateAlerts()
    }

    /// Hands every connected tool's numbers to the widget (and 0.1's file for Claude Code).
    func publishToWidget() {
        guard let folder = groupFolder else { return }
        var tools: [ToolSnapshot] = []
        if let snapshot { tools.append(ToolSnapshot(tool: .claudeCode, usage: snapshot)) }
        if codexConnected, let codexSnapshot { tools.append(ToolSnapshot(tool: .codex, usage: codexSnapshot)) }
        if AppGroupFiles.publishTools(tools, to: folder, now: now) { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Codex

    /// Runs the Codex reader. New good numbers replace the old ones; a failed read never does
    /// (lesson 12), so a format change keeps the last numbers and lets "as of" go stale.
    func refreshCodex() {
        guard codexConnected else { return }
        now = Date()
        let reading = CodexReader.read(paths: codexPaths, now: now)
        codexStatus = reading.status
        if let usage = reading.usage, SnapshotPolicy.shouldReplace(current: codexSnapshot, with: usage, now: now) {
            codexSnapshot = usage
            try? CodexStore.save(usage, paths: paths)
        }
        publishToWidget()
        evaluateAlerts()
    }

    func connectCodex() {
        codexConnected = true
        defaults.set(true, forKey: Keys.codexConnected)
        startCodexWatcher()
        refreshCodex()
    }

    /// Stops watching, and removes Codex's numbers from Wiggleroom and the widget.
    /// Nothing in Codex's own folder is touched.
    func disconnectCodex() {
        codexWatcher?.stop()
        codexWatcher = nil
        codexWatcherState = .stopped
        codexConnected = false
        defaults.set(false, forKey: Keys.codexConnected)
        codexSnapshot = nil
        CodexStore.remove(paths: paths)
        publishToWidget()
    }

    /// "Check again" after installing Codex.
    func checkCodexAgain() {
        codexWatcher?.arm()
        if codexConnected { refreshCodex() } else { objectWillChange.send() }
    }

    var codexInstalled: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: codexPaths.codexFolder.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func startCodexWatcher() {
        let w = codexWatcher ?? CodexWatcher(paths: codexPaths)
        w.onChange = { [weak self] in self?.refreshCodex() }
        w.onState = { [weak self] s in self?.codexWatcherState = s }
        codexWatcher = w
        w.start()
        codexWatcherState = w.state
    }

    var codexDisplay: UsageDisplay? {
        codexSnapshot.map { UsageFormatter.display($0, context: DisplayContext(now: now)) }
    }

    /// Every connected tool with numbers, closest to a limit first.
    var toolDisplays: [ToolDisplay] {
        var out: [ToolDisplay] = []
        if let d = display { out.append(ToolDisplay(tool: .claudeCode, display: d)) }
        if codexConnected, let d = codexDisplay { out.append(ToolDisplay(tool: .codex, display: d)) }
        return ToolDisplay.closestFirst(out)
    }

    var connectedTools: [Tool] {
        var out: [Tool] = []
        if isConnected || snapshot != nil { out.append(.claudeCode) }
        if codexConnected { out.append(.codex) }
        return out
    }

    var codexStatusText: String {
        CodexStatusText.text(connected: codexConnected, installed: codexInstalled, status: codexStatus,
                             watching: codexWatcherState == .watching, hasNumbers: codexSnapshot != nil)
    }

    var display: UsageDisplay? {
        snapshot.map { UsageFormatter.display($0, context: DisplayContext(now: now)) }
    }

    var cardContent: CardContent {
        if let d = display { return .usage(d) }
        return .empty
    }

    // MARK: Claude Code connection

    func refreshConnection() {
        connection = connectionHelper.status()
    }

    /// True when the setting points at a Wiggleroom in another place (the app was moved).
    var connectedElsewhere: Bool {
        if case .connected(let c) = connection { return c.executablePath != HelperLocation.executablePath }
        return false
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    func connect() {
        report(connectionHelper.connect())
    }

    func disconnect() {
        report(connectionHelper.disconnect())
    }

    private func report(_ outcome: Connection.Outcome) {
        switch outcome {
        case .done(let summary, let backup):
            lastMessage = backup.map { "\(summary) A backup of your previous settings is at \($0.path)." } ?? summary
            lastBackup = backup
        case .refused(let why):
            lastMessage = why
        }
        refreshConnection()
    }

    // MARK: Alerts

    private func saveAlerts() {
        if let d = try? JSONEncoder().encode(alerts) { defaults.set(d, forKey: Keys.alerts) }
        // Ask macOS for permission only when alerts are on and the user hasn't been asked yet.
        if alerts.enabled && notificationsAllowed == nil { requestNotificationPermission() }
    }

    /// Alerts are only planned (and recorded as sent) when macOS will actually show them, so a
    /// week's alert isn't marked as sent while notifications are still off.
    func evaluateAlerts() {
        guard notificationsAllowed == true else { return }
        let record = defaults.data(forKey: Keys.alertRecord).flatMap { try? JSONDecoder().decode(AlertRecord.self, from: $0) } ?? AlertRecord()
        var tools: [ToolSnapshot] = []
        if let snapshot { tools.append(ToolSnapshot(tool: .claudeCode, usage: snapshot)) }
        if codexConnected, let codexSnapshot { tools.append(ToolSnapshot(tool: .codex, usage: codexSnapshot)) }
        let result = AlertPlanner.evaluate(tools: tools, settings: alerts, record: record, now: Date())
        if result.record != record, let d = try? JSONEncoder().encode(result.record) { defaults.set(d, forKey: Keys.alertRecord) }
        for alert in result.alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body(context: DisplayContext(now: Date()))
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil))
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.notificationsAllowed = granted
                self.evaluateAlerts()
            }
        }
    }

    func refreshNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self.notificationsAllowed = status == .notDetermined ? nil : (status == .authorized || status == .provisional)
                if status == .notDetermined && self.alerts.enabled && self.setupDone {
                    // Alerts are on by default, so ask once even if the toggle was never touched.
                    self.requestNotificationPermission()
                } else {
                    self.evaluateAlerts()
                }
            }
        }
    }

    // MARK: Login item

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastMessage = "macOS didn't change the login setting: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Data

    func revealDataFile() {
        let target = FileManager.default.fileExists(atPath: paths.usageFile.path) ? paths.usageFile : paths.supportFolder
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// Disconnects (so the file isn't recreated), then removes every file Wiggleroom made.
    func deleteAllData() {
        var notes: [String] = []
        if isConnected {
            switch connectionHelper.disconnect() {
            case .done(let summary, _): notes.append(summary)
            case .refused(let why): notes.append(why)
            }
        }
        if codexConnected { disconnectCodex() }
        let problems = DataEraser.eraseAll(paths: paths, appGroupFolder: groupFolder)
        if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        snapshot = nil
        WidgetCenter.shared.reloadAllTimelines()
        showMenuBar = false
        menuBarChoice = .default
        alerts = .default
        notes.append(problems.isEmpty ? "All Wiggleroom data was deleted." : "Some files couldn't be deleted: \(problems.joined(separator: "; ")).")
        lastMessage = notes.joined(separator: " ")
        refreshConnection()
        watcher?.arm()
    }

    // MARK: Status text

    var watcherText: String {
        switch watcherState {
        case .starting: "Starting…"
        case .watching: "Watching for new numbers from Claude Code"
        case .problem(let why): "Not watching: \(why)"
        }
    }

    var isWatching: Bool { watcherState == .watching }

    var canShareWithWidget: Bool { groupFolder != nil }

    func openNotificationSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(u) }
    }

    func quit() { NSApp.terminate(nil) }

    var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
