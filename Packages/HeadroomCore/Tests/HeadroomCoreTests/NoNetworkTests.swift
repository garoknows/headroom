import Foundation
import Testing

/// PRD section 4: no networking, Keychain or claude.ai access anywhere in Headroom's code.
/// Scans every Swift file and script of the app, widget, core package and tools.
@Suite struct NoNetworkTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// What must never appear. Each is a networking API, a credential store or a disallowed source.
    static let forbidden = [
        "URLSession", "NSURLConnection", "NSURLSession", "URLRequest", "NSURLRequest", "dataTask(",
        "import Network", "NWConnection", "NWListener", "NWPathMonitor", "NWBrowser",
        "CFSocket", "CFStreamCreatePairWithSocket", "CFNetwork", "socket(", "getaddrinfo", "gethostbyname",
        "WKWebView", "import WebKit", "HTTPCookie", "SecItemCopyMatching", "SecItemAdd", "SecKeychain",
        "Claude Code-credentials", "api.anthropic.com", "oauth", "claude.ai/api",
        "curl ", "wget ", "contentsOf: URL(string: \"http",
    ]

    static func sourceFiles() -> [URL] {
        let folders = ["Packages/HeadroomCore/Sources", "App", "Widgets", "tools"]
        var out: [URL] = []
        for f in folders {
            let dir = repoRoot.appendingPathComponent(f)
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where ["swift", "sh", "py", "m", "c", "h", "plist", "entitlements"].contains(url.pathExtension) {
                out.append(url)
            }
        }
        return out
    }

    static func hits(in files: [URL]) -> [String] {
        var found: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for word in forbidden where text.range(of: word, options: .caseInsensitive) != nil {
                found.append("\(file.lastPathComponent): \(word)")
            }
        }
        return found
    }

    @Test func noNetworkingKeychainOrClaudeAccountCode() {
        let files = Self.sourceFiles()
        #expect(files.count >= 10, "the scan found too few files; is the folder layout right?")
        #expect(files.contains { $0.lastPathComponent == "main.swift" })
        #expect(Self.hits(in: files) == [])
    }

    @Test func entitlementsHaveNoNetworkAccess() throws {
        let files = Self.sourceFiles().filter { $0.pathExtension == "entitlements" }
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(!text.contains("network.client") && !text.contains("network.server"), "\(f.lastPathComponent)")
        }
    }

    /// Proves the scan can fail: a planted file with a networking call is caught (lesson 17).
    @Test func scanCatchesAPlantedNetworkCall() throws {
        let dir = testTempRoot().appendingPathComponent("hr-net-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let planted = dir.appendingPathComponent("Planted.swift")
        try "let t = URLSession.shared.dataTask(with: u)".write(to: planted, atomically: false, encoding: .utf8)
        #expect(Self.hits(in: [planted]).count == 2)
    }
}
