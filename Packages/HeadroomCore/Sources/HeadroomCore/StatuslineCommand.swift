import Foundation

/// The command Headroom puts in Claude Code's `statusLine` setting, and how to read it back.
///
/// Form (one line, run by Claude Code with /bin/sh):
///
///     [ -x '<helper>' ] && exec '<helper>' --then <b64> || eval "$(printf %s <b64> | /usr/bin/base64 -D)"
///
/// where <b64> is the user's previous status line command in base64. Normally the shell runs
/// Headroom's helper, which saves the numbers and runs the previous command. If Headroom was
/// deleted without disconnecting, the shell runs the previous command by itself, so the user's
/// status line keeps working. With no previous command: `[ -x '<helper>' ] && exec '<helper>' || true`.
/// Keeping the previous command inside the setting means it can't get lost even if Headroom's
/// own files are deleted.
public struct StatuslineCommand: Equatable, Sendable {
    public static let executableName = "headroom-statusline"
    public static let thenFlag = "--then"

    public var executablePath: String
    /// The status line command that was there before Headroom, run after Headroom saves the numbers.
    public var previous: String?

    public init(executablePath: String, previous: String?) {
        self.executablePath = executablePath
        let trimmed = previous?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.previous = (trimmed?.isEmpty ?? true) ? nil : previous
    }

    public var commandLine: String {
        let q = Self.shellQuote(executablePath)
        guard let previous else { return "[ -x \(q) ] && exec \(q) || true" }
        let b64 = Data(previous.utf8).base64EncodedString()
        return "[ -x \(q) ] && exec \(q) \(Self.thenFlag) \(b64) || eval \"$(printf %s \(b64) | /usr/bin/base64 -D)\""
    }

    /// Reads a status line command. Returns nil if it isn't one of Headroom's.
    /// Accepts the current form (only exactly as Headroom writes it) and the plain early form
    /// `'<helper>' [--then <b64>]`.
    public static func parse(_ command: String) -> StatuslineCommand? {
        let c = command.trimmingCharacters(in: .whitespaces)
        if c.hasPrefix("[ -x ") {
            guard let (path, _) = readQuoted(c.dropFirst(5)) else { return nil }
            var previous: String?
            if let r = c.range(of: " \(thenFlag) ") {
                let b64 = String(c[r.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) })
                guard let p = decodePrevious(b64) else { return nil }
                previous = p
            }
            let candidate = StatuslineCommand(executablePath: path, previous: previous)
            guard isHelperPath(path), candidate.commandLine == c else { return nil }
            return candidate
        }
        // The plain form.
        var path = ""
        var rest = Substring(c)
        if c.hasPrefix("'") {
            guard let (p, r) = readQuoted(Substring(c)) else { return nil }
            path = p; rest = r
        } else {
            let parts = c.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            path = String(parts.first ?? "")
            rest = parts.count > 1 ? " " + parts[1] : ""
        }
        guard isHelperPath(path) else { return nil }
        let args = rest.split(separator: " ", omittingEmptySubsequences: true)
        if args.isEmpty { return StatuslineCommand(executablePath: path, previous: nil) }
        guard args.count == 2, args[0] == thenFlag, let prev = decodePrevious(String(args[1])) else { return nil }
        return StatuslineCommand(executablePath: path, previous: prev)
    }

    static func isHelperPath(_ path: String) -> Bool {
        path.hasPrefix("/") && (path as NSString).lastPathComponent == executableName
    }

    /// Reads a single-quoted shell word at the start of `s` ('\'' stands for a quote inside).
    /// Returns its text and what follows it.
    static func readQuoted(_ s: Substring) -> (String, Substring)? {
        guard s.hasPrefix("'") else { return nil }
        var out = ""
        var idx = s.index(after: s.startIndex)
        while idx < s.endIndex {
            if s[idx] == "'" {
                if s[idx...].hasPrefix("'\\''") { out.append("'"); idx = s.index(idx, offsetBy: 4); continue }
                return (out, s[s.index(after: idx)...])
            }
            out.append(s[idx]); idx = s.index(after: idx)
        }
        return nil
    }

    /// The previous command from its base64 form, or nil if the text isn't valid.
    public static func decodePrevious(_ b64: String) -> String? {
        guard !b64.isEmpty, b64.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) }),
              let data = Data(base64Encoded: b64), let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    /// Wraps text in single quotes for the shell.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
