import Foundation

/// The command Headroom puts in Claude Code's `statusLine` setting, and how to read it back.
///
/// Form: `'/path/to/headroom-statusline'` or `'/path/to/headroom-statusline' --then <base64>`,
/// where the base64 text is the user's previous status line command. Keeping the previous command
/// inside the setting itself means it can't get lost, even if Headroom's own files are deleted.
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
        var s = Self.shellQuote(executablePath)
        if let previous { s += " \(Self.thenFlag) " + Data(previous.utf8).base64EncodedString() }
        return s
    }

    /// Reads a status line command. Returns nil if it isn't one of Headroom's.
    public static func parse(_ command: String) -> StatuslineCommand? {
        let c = command.trimmingCharacters(in: .whitespaces)
        var path = ""
        var rest = Substring(c)
        if c.hasPrefix("'") {
            // A single-quoted path; a quote inside is written as '\'' .
            var idx = c.index(after: c.startIndex)
            var closed = false
            while idx < c.endIndex {
                if c[idx] == "'" {
                    if c[idx...].hasPrefix("'\\''") { path.append("'"); idx = c.index(idx, offsetBy: 4); continue }
                    idx = c.index(after: idx); closed = true; break
                }
                path.append(c[idx]); idx = c.index(after: idx)
            }
            guard closed else { return nil }
            rest = c[idx...]
        } else {
            let parts = c.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            path = String(parts.first ?? "")
            rest = parts.count > 1 ? " " + parts[1] : ""
        }
        guard path.hasPrefix("/"), (path as NSString).lastPathComponent == executableName else { return nil }
        let args = rest.split(separator: " ", omittingEmptySubsequences: true)
        if args.isEmpty { return StatuslineCommand(executablePath: path, previous: nil) }
        guard args.count == 2, args[0] == thenFlag, let prev = decodePrevious(String(args[1])) else { return nil }
        return StatuslineCommand(executablePath: path, previous: prev)
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
