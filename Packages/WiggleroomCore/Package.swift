// swift-tools-version:6.0
import PackageDescription

// WiggleroomCore: everything that can be tested without a Mac app around it.
//  - WiggleroomCore: parsing Claude Code's status line JSON, the snapshot file, display text,
//    alerts and the Claude Code settings editor. Foundation only.
//  - WiggleroomUI: the SwiftUI cards shared by the widget, the menu bar popover and the renders.
//  - wiggleroom-statusline: the tiny command Claude Code runs on every update.
let package = Package(
    name: "WiggleroomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WiggleroomCore", targets: ["WiggleroomCore"]),
        .library(name: "WiggleroomUI", targets: ["WiggleroomUI"]),
        .executable(name: "wiggleroom-statusline", targets: ["wiggleroom-statusline"]),
    ],
    targets: [
        .target(name: "WiggleroomCore"),
        .target(name: "WiggleroomUI", dependencies: ["WiggleroomCore"]),
        .executableTarget(name: "wiggleroom-statusline", dependencies: ["WiggleroomCore"]),
        .testTarget(
            name: "WiggleroomCoreTests",
            dependencies: ["WiggleroomCore"],
            exclude: ["Fixtures"]
        ),
        // Runs the real wiggleroom-statusline binary as Claude Code would.
        .testTarget(name: "StatuslineTests", dependencies: ["WiggleroomCore", "wiggleroom-statusline"]),
    ]
)
