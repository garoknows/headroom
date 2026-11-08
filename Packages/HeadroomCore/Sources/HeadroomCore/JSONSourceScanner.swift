import Foundation

/// A small JSON reader that remembers where each value sits in the original text, so Headroom
/// can change one value in Claude Code's settings file and leave every other byte exactly as
/// the user wrote it (their spacing, key order and any comments).
///
/// It accepts standard JSON plus `//` and `/* */` comments and trailing commas, because some
/// people keep those in hand-edited settings files.
struct JSONSourceScanner {
    struct Node {
        enum Kind: Equatable { case object, array, string, number, bool, null }
        var kind: Kind
        /// Byte range of the value in the source (for a string, including its quotes).
        var range: Range<Int>
        var members: [Member] = []
        var elements: [Node] = []
        /// Decoded text of a string value.
        var string: String?
    }

    struct Member {
        var key: String
        var keyRange: Range<Int>
        var value: Node
    }

    struct Failure: Error, Equatable { var offset: Int; var reason: String }

    private let b: [UInt8]
    private var i = 0
    private(set) var sawComments = false
    private(set) var sawTrailingCommas = false
    private var depth = 0

    init(_ bytes: [UInt8]) { b = bytes }

    /// Parses a whole document. Leading UTF-8 byte order mark and surrounding whitespace allowed.
    static func parse(_ bytes: [UInt8]) -> Result<(Node, JSONSourceScanner), Failure> {
        var s = JSONSourceScanner(bytes)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { s.i = 3 }
        do {
            try s.skipSpace()
            let node = try s.value()
            try s.skipSpace()
            guard s.i == s.b.count else { throw Failure(offset: s.i, reason: "extra text after the end") }
            return .success((node, s))
        } catch let f as Failure {
            return .failure(f)
        } catch {
            return .failure(Failure(offset: s.i, reason: "unreadable"))
        }
    }

    private mutating func skipSpace() throws {
        while i < b.count {
            switch b[i] {
            case 0x20, 0x09, 0x0A, 0x0D: i += 1
            case 0x2F where i + 1 < b.count && b[i + 1] == 0x2F: // line comment
                sawComments = true
                while i < b.count && b[i] != 0x0A { i += 1 }
            case 0x2F where i + 1 < b.count && b[i + 1] == 0x2A: // block comment
                sawComments = true
                i += 2
                while i + 1 < b.count && !(b[i] == 0x2A && b[i + 1] == 0x2F) { i += 1 }
                guard i + 1 < b.count else { throw Failure(offset: i, reason: "comment never closed") }
                i += 2
            default: return
            }
        }
    }

    private mutating func value() throws -> Node {
        guard i < b.count else { throw Failure(offset: i, reason: "unexpected end") }
        switch b[i] {
        case 0x7B: return try object()
        case 0x5B: return try array()
        case 0x22:
            let start = i
            let s = try string()
            return Node(kind: .string, range: start..<i, string: s)
        case 0x74: return try literal("true", .bool)
        case 0x66: return try literal("false", .bool)
        case 0x6E: return try literal("null", .null)
        case 0x2D, 0x30...0x39: return try number()
        default: throw Failure(offset: i, reason: "unexpected character")
        }
    }

    private mutating func object() throws -> Node {
        depth += 1
        guard depth < 200 else { throw Failure(offset: i, reason: "nested too deeply") }
        defer { depth -= 1 }
        let start = i
        i += 1
        var members: [Member] = []
        try skipSpace()
        if i < b.count && b[i] == 0x7D { i += 1; return Node(kind: .object, range: start..<i) }
        while true {
            try skipSpace()
            if i < b.count && b[i] == 0x7D, !members.isEmpty { sawTrailingCommas = true; i += 1; break }
            guard i < b.count && b[i] == 0x22 else { throw Failure(offset: i, reason: "expected a key") }
            let keyStart = i
            let key = try string()
            let keyRange = keyStart..<i
            try skipSpace()
            guard i < b.count && b[i] == 0x3A else { throw Failure(offset: i, reason: "expected ':'") }
            i += 1
            try skipSpace()
            members.append(Member(key: key, keyRange: keyRange, value: try value()))
            try skipSpace()
            guard i < b.count else { throw Failure(offset: i, reason: "object never closed") }
            if b[i] == 0x2C { i += 1; continue }
            if b[i] == 0x7D { i += 1; break }
            throw Failure(offset: i, reason: "expected ',' or '}'")
        }
        return Node(kind: .object, range: start..<i, members: members)
    }

    private mutating func array() throws -> Node {
        depth += 1
        guard depth < 200 else { throw Failure(offset: i, reason: "nested too deeply") }
        defer { depth -= 1 }
        let start = i
        i += 1
        var elements: [Node] = []
        try skipSpace()
        if i < b.count && b[i] == 0x5D { i += 1; return Node(kind: .array, range: start..<i) }
        while true {
            try skipSpace()
            if i < b.count && b[i] == 0x5D, !elements.isEmpty { sawTrailingCommas = true; i += 1; break }
            elements.append(try value())
            try skipSpace()
            guard i < b.count else { throw Failure(offset: i, reason: "array never closed") }
            if b[i] == 0x2C { i += 1; continue }
            if b[i] == 0x5D { i += 1; break }
            throw Failure(offset: i, reason: "expected ',' or ']'")
        }
        return Node(kind: .array, range: start..<i, elements: elements)
    }

    private mutating func literal(_ word: String, _ kind: Node.Kind) throws -> Node {
        let w = Array(word.utf8)
        guard i + w.count <= b.count, Array(b[i..<i + w.count]) == w else { throw Failure(offset: i, reason: "unexpected word") }
        let start = i
        i += w.count
        return Node(kind: kind, range: start..<i)
    }

    private mutating func number() throws -> Node {
        let start = i
        if b[i] == 0x2D { i += 1 }
        func digits() -> Int { let s = i; while i < b.count && (0x30...0x39).contains(b[i]) { i += 1 }; return i - s }
        guard digits() > 0 else { throw Failure(offset: i, reason: "bad number") }
        if i < b.count && b[i] == 0x2E { i += 1; guard digits() > 0 else { throw Failure(offset: i, reason: "bad number") } }
        if i < b.count && (b[i] == 0x65 || b[i] == 0x45) {
            i += 1
            if i < b.count && (b[i] == 0x2B || b[i] == 0x2D) { i += 1 }
            guard digits() > 0 else { throw Failure(offset: i, reason: "bad number") }
        }
        return Node(kind: .number, range: start..<i)
    }

    /// Reads a string starting at the opening quote and returns its decoded text.
    private mutating func string() throws -> String {
        i += 1
        var out: [UInt8] = []
        while i < b.count {
            let c = b[i]
            if c == 0x22 { i += 1; return String(decoding: out, as: UTF8.self) }
            if c < 0x20 { throw Failure(offset: i, reason: "control character in a string") }
            if c == 0x5C {
                guard i + 1 < b.count else { break }
                let e = b[i + 1]
                i += 2
                switch e {
                case 0x22: out.append(0x22)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), i + 1 < b.count, b[i] == 0x5C, b[i + 1] == 0x75 {
                        i += 2
                        let low = try hex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw Failure(offset: i, reason: "bad escape") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw Failure(offset: i, reason: "bad escape") }
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: throw Failure(offset: i, reason: "bad escape")
                }
                continue
            }
            out.append(c)
            i += 1
        }
        throw Failure(offset: i, reason: "string never closed")
    }

    private mutating func hex4() throws -> UInt32 {
        guard i + 4 <= b.count, let v = UInt32(String(decoding: b[i..<i + 4], as: UTF8.self), radix: 16) else {
            throw Failure(offset: i, reason: "bad escape")
        }
        i += 4
        return v
    }
}
