import Foundation

/// What `headroom-statusline` does with one update from Claude Code, apart from passing it on.
/// Kept here (not in the command's own file) so tests can run it directly.
public enum StatuslineRecorder {
    public enum Outcome: Equatable {
        case wrote
        /// The update had no `rate_limits`; the last good file was left alone.
        case nothingToRecord
        case failed
    }

    /// Reads the limits from `payload`, merges them with the file on disk and writes the result
    /// atomically with 0600 permissions. Never throws: any problem means "write nothing".
    @discardableResult
    public static func record(payload: Data, paths: HeadroomPaths, now: Date = Date()) -> Outcome {
        guard let incoming = RateLimitParser.snapshot(fromStatusLine: payload, now: now) else { return .nothingToRecord }
        do {
            try SecureFile.ensurePrivateFolder(paths.supportFolder)
            // Two Claude Code windows can update at the same moment. A short lock keeps their
            // merges in order; if it isn't free quickly, write anyway (the rename is still atomic).
            let lock = SecureFile.lock(paths.lockFile, budget: 0.02)
            defer { if let lock { close(lock) } }
            let existing = SecureFile.readSmallFile(paths.usageFile).flatMap(UsageSnapshot.decode)
            let merged = SnapshotPolicy.merge(existing: existing, incoming: incoming, now: now)
            if merged == existing { return .wrote }
            try SecureFile.atomicWrite(try merged.encoded(), to: paths.usageFile, mode: 0o600)
            return .wrote
        } catch {
            return .failed
        }
    }
}
