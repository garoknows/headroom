import Foundation

/// Reads the JSON that Claude Code passes to a status line command and keeps only the
/// `rate_limits` numbers. Everything else in that JSON (folders, session ID, model, cost,
/// transcript path and so on) is never looked at or kept.
public enum RateLimitParser {
    /// A snapshot from one status line update, or nil when there is nothing usable
    /// (no `rate_limits`, as with API key sign-in or before the session's first reply).
    public static func snapshot(fromStatusLine data: Data, now: Date) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let top = object as? [String: Any],
              let rateLimits = top["rate_limits"] as? [String: Any] else { return nil }
        var limits: [LimitWindow] = []
        for (id, value) in rateLimits {
            guard LimitKind.isSupported(id), let window = value as? [String: Any],
                  let raw = percent(window["used_percentage"]) else { continue }
            let clamped = min(100, max(0, raw))
            limits.append(LimitWindow(id: id, usedPercent: clamped, outOfRange: clamped != raw,
                                      resetsAt: date(window["resets_at"])))
        }
        guard !limits.isEmpty else { return nil }
        return UsageSnapshot(updatedAt: now, limits: LimitKind.sorted(limits))
    }

    /// A finite number, given as a JSON number or a numeric string. Booleans don't count.
    static func percent(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite ? d : nil
        case let s as String:
            guard let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite else { return nil }
            return d
        default:
            return nil
        }
    }

    /// Earliest and latest reset times Headroom believes. Anything outside is treated as unknown.
    static let plausibleDates = Date(timeIntervalSince1970: 1_577_836_800)...Date(timeIntervalSince1970: 4_102_444_800) // 2020 to 2100

    /// `resets_at` as Unix seconds (the documented form), Unix milliseconds, a numeric string,
    /// or an ISO 8601 string (seen in some Claude Code versions).
    public static func date(_ value: Any?) -> Date? {
        let result: Date?
        switch value {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            result = fromEpoch(n.doubleValue)
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespaces)
            if let d = Double(t) { result = fromEpoch(d) } else { result = iso8601(t) }
        default:
            result = nil
        }
        guard let result, plausibleDates.contains(result) else { return nil }
        return result
    }

    private static func fromEpoch(_ v: Double) -> Date? {
        guard v.isFinite, v > 0 else { return nil }
        // Seconds today are about 1.8e9; milliseconds about 1.8e12.
        return Date(timeIntervalSince1970: v > 100_000_000_000 ? v / 1000 : v)
    }

    private static func iso8601(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: s)
    }
}
