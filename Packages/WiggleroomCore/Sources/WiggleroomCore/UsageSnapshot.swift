import Foundation

/// One usage limit, as Wiggleroom stores it: which limit, how much is used, and when it resets.
/// Nothing else from Claude Code's status line data is ever kept.
public struct LimitWindow: Codable, Equatable, Sendable {
    /// The limit's name as Claude Code reports it, for example `five_hour` or `seven_day`.
    public var id: String
    /// Percent used, always between 0 and 100.
    public var usedPercent: Double
    /// True when Claude Code reported a number below 0 or above 100 and Wiggleroom clamped it.
    public var outOfRange: Bool
    /// When this limit resets (an absolute moment, stored as UTC seconds). Nil when unknown.
    public var resetsAt: Date?

    public init(id: String, usedPercent: Double, outOfRange: Bool = false, resetsAt: Date?) {
        self.id = id
        self.usedPercent = usedPercent
        self.outOfRange = outOfRange
        self.resetsAt = resetsAt
    }
}

/// The whole file Wiggleroom writes: a format number, when the numbers were seen, and the limits.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    /// The only keys a snapshot file may contain. A test checks the script's output against these.
    public static let allowedKeys: Set<String> = ["format", "updatedAt", "limits"]
    public static let allowedLimitKeys: Set<String> = ["id", "usedPercent", "outOfRange", "resetsAt"]

    public var format: Int
    /// When Claude Code last handed these numbers over.
    public var updatedAt: Date
    public var limits: [LimitWindow]

    public init(format: Int = UsageSnapshot.currentFormat, updatedAt: Date, limits: [LimitWindow]) {
        self.format = format
        self.updatedAt = updatedAt
        self.limits = limits
    }

    public func limit(_ id: String) -> LimitWindow? { limits.first { $0.id == id } }

    // MARK: Encoding (dates as plain UTC seconds, sorted keys, so files are small and stable)

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) -> UsageSnapshot? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(UsageSnapshot.self, from: data)
    }
}

/// Known limit names and the order they are shown in.
public enum LimitKind {
    public static let session = "five_hour"
    public static let weekly = "seven_day"
    public static let spend = "spend_limit"

    /// Limit names Wiggleroom understands. Anything else from Claude Code is ignored.
    /// `seven_day_<name>` covers model-specific weekly limits if Claude Code ever reports them.
    public static func isSupported(_ id: String) -> Bool {
        guard isWellFormed(id) else { return false }
        if id == session || id == weekly || id == spend { return true }
        return id.hasPrefix(weekly + "_") && id.count > weekly.count + 1
    }

    /// Lowercase letters, digits and underscores, starting with a letter, at most 40 characters.
    public static func isWellFormed(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, id.unicodeScalars.count <= 40,
              ("a"..."z").contains(first) else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    static func sortKey(_ id: String) -> (Int, String) {
        switch id {
        case session: (0, id)
        case weekly: (1, id)
        case spend: (3, id)
        default: (2, id)
        }
    }

    public static func sorted(_ limits: [LimitWindow]) -> [LimitWindow] {
        limits.sorted { sortKey($0.id) < sortKey($1.id) }
    }
}
