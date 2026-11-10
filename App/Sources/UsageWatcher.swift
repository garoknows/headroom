import AppKit
import Foundation
import WiggleroomCore

/// Watches Wiggleroom's data folder for the status line program's writes, using file system
/// events (no polling loop). It checks its own health every minute and after sleep, wake and
/// user switching, and re-arms itself if anything went wrong (lesson 13). `state` is the real
/// state, so the UI only says "Watching" when it really is.
@MainActor
final class UsageWatcher {
    enum State: Equatable {
        case starting
        case watching
        case problem(String)
    }

    private(set) var state: State = .starting { didSet { if state != oldValue { onState?(state) } } }
    var onChange: (() -> Void)?
    var onState: ((State) -> Void)?

    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private var watchedInode: ino_t = 0
    private var healthTimer: Timer?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(folder: URL) { self.folder = folder }

    func start() {
        arm()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.arm()
                    self?.onChange?()   // anything written while asleep or switched away
                }
            })
        }
    }

    /// Opens the folder and listens for changes. Creates the folder (0700) if it's missing,
    /// so there is always something to watch, even before the first Claude Code reply.
    func arm() {
        source?.cancel()
        source = nil
        do {
            try SecureFile.ensurePrivateFolder(folder)
        } catch {
            state = .problem("Wiggleroom can't create its data folder.")
            return
        }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { state = .problem("Wiggleroom can't watch its data folder."); return }
        var st = stat()
        fstat(fd, &st)
        watchedInode = st.st_ino
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: .main)
        s.setEventHandler { [weak self, weak s] in
            MainActor.assumeIsolated {
                guard let self, let s else { return }
                if !s.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                    self.arm()   // the folder itself went away or moved: start over
                }
                self.scheduleChange()
            }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        state = .watching
    }

    /// Several writes in a row (two Claude Code windows) become one update.
    private func scheduleChange() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange?() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    /// Re-arms if the watch was lost or the folder was replaced.
    func checkHealth() {
        var st = stat()
        let folderOK = lstat(folder.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
        if source == nil || source?.isCancelled == true || !folderOK || st.st_ino != watchedInode {
            arm()
            onChange?()
        }
    }
}
