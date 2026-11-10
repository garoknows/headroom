import AppKit
import CoreServices
import Foundation
import WiggleroomCore

/// Watches Codex's sessions folder (and everything below it) for changes, using macOS file
/// system events: no polling loop, nothing written, nothing opened here. Each change just asks
/// the app to run the Codex reader again. Like the Claude Code watcher, it checks itself every
/// minute and after sleep, wake and user switching, and starts over if anything went wrong
/// (lesson 13); the minute check also re-reads, as a safety net.
@MainActor
final class CodexWatcher {
    enum State: Equatable {
        case stopped
        case watching
        /// Codex isn't installed (yet). The minute check keeps looking for it.
        case waitingForCodex
    }

    private(set) var state: State = .stopped { didSet { if state != oldValue { onState?(state) } } }
    var onChange: (() -> Void)?
    var onState: ((State) -> Void)?

    private let paths: CodexPaths
    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(paths: CodexPaths) { self.paths = paths }

    func start() {
        guard timer == nil else { return }
        arm()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkHealth()
                self?.onChange?()
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.arm()
                    self?.onChange?()
                }
            })
        }
    }

    func stop() {
        tearDown()
        timer?.invalidate()
        timer = nil
        pending?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        state = .stopped
    }

    /// The deepest folder that exists: `~/.codex/sessions`, or `~/.codex` until Codex creates it.
    private func target() -> String? {
        var isDir: ObjCBool = false
        for url in [paths.sessionsFolder, paths.codexFolder] {
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url.path }
        }
        return nil
    }

    func arm() {
        tearDown()
        guard let path = target() else { state = .waitingForCodex; return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<CodexWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.scheduleChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &context, [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else {
            state = .waitingForCodex
            return
        }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            state = .waitingForCodex
            return
        }
        stream = s
        watchedPath = path
        state = .watching
    }

    private func tearDown() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        stream = nil
        watchedPath = nil
    }

    /// Codex writes in bursts; many changes in a row become one re-read.
    private func scheduleChange() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange?() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// Starts over if the watch was lost, or if a better folder to watch has appeared.
    func checkHealth() {
        if stream == nil || target() != watchedPath { arm() }
    }
}
