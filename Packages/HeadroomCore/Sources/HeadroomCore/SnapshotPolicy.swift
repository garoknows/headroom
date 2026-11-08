import Foundation

/// Rules for combining and trusting snapshots. Pure functions, so every rule is tested.
public enum SnapshotPolicy {
    /// How long a limit whose reset has passed is kept, so the widget can say
    /// "Reset at 1:00 AM, waiting for new numbers" instead of guessing.
    public static let keepPassedFor: TimeInterval = 7 * 24 * 3600

    /// Combines what is already on disk with a new update.
    /// - The newest update time wins (two Claude Code sessions can write at nearly the same time).
    /// - For one limit, the later reset time wins: a session holding numbers from an older
    ///   window never replaces numbers from the current one.
    /// - A limit missing from the update is kept only if its reset has already passed
    ///   (Claude Code drops a window once it resets), so the reset-passed state can show.
    public static func merge(existing: UsageSnapshot?, incoming: UsageSnapshot, now: Date) -> UsageSnapshot {
        guard let existing, isPlausible(existing, now: now) else { return incoming }
        if existing.updatedAt > incoming.updatedAt { return existing }
        var result: [LimitWindow] = []
        for new in incoming.limits {
            if let old = existing.limit(new.id), let oldReset = old.resetsAt, let newReset = new.resetsAt,
               oldReset.timeIntervalSince(newReset) > 60 {
                result.append(old)
            } else {
                result.append(new)
            }
        }
        for old in existing.limits where incoming.limit(old.id) == nil {
            if let reset = old.resetsAt, reset <= now, now.timeIntervalSince(reset) < keepPassedFor {
                result.append(old)
            }
        }
        return UsageSnapshot(updatedAt: incoming.updatedAt, limits: LimitKind.sorted(result))
    }

    /// Whether a snapshot is sane enough to show. Anything odd is rejected, never "fixed up".
    public static func isPlausible(_ s: UsageSnapshot, now: Date) -> Bool {
        guard s.format == UsageSnapshot.currentFormat, !s.limits.isEmpty, s.limits.count <= 12,
              RateLimitParser.plausibleDates.contains(s.updatedAt),
              s.updatedAt <= now.addingTimeInterval(10 * 60) else { return false }
        var seen = Set<String>()
        for l in s.limits {
            guard LimitKind.isSupported(l.id), seen.insert(l.id).inserted,
                  l.usedPercent.isFinite, (0...100).contains(l.usedPercent) else { return false }
            if let r = l.resetsAt, !RateLimitParser.plausibleDates.contains(r) { return false }
        }
        return true
    }

    /// Whether the helper app should copy `candidate` over the snapshot the widget shows now.
    /// Never replaces good data with bad data (lesson 12), and never with older data.
    public static func shouldReplace(current: UsageSnapshot?, with candidate: UsageSnapshot?, now: Date) -> Bool {
        guard let candidate, isPlausible(candidate, now: now) else { return false }
        guard let current, isPlausible(current, now: now) else { return true }
        if candidate == current { return false }
        return candidate.updatedAt >= current.updatedAt
    }
}
