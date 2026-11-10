// swift-tools-version:6.0
import PackageDescription

// WiggleroomCore: everything that can be tested without a Mac app around it.
//  - WiggleroomCore: parsing Claude Code's status line JSON, the snapshot file, display text,
//    alerts and the Claude Code settings editor. Foundation only.
//  - WiggleroomUI: the SwiftUI cards shared by the widget, the menu bar popover and the renders.
//  - WiggleroomWindows: the setup window, the Settings window and the menu bar popover (app only),
//    kept here so the renders and the layout tests can draw them at their real size.
//  - wiggleroom-statusline: the tiny command Claude Code runs on every update.
let package = Package(
    name: "WiggleroomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WiggleroomCore", targets: ["WiggleroomCore"]),
        .library(name: "WiggleroomUI", targets: ["WiggleroomUI"]),
        .library(name: "WiggleroomWindows", targets: ["WiggleroomWindows"]),
        .executable(name: "wiggleroom-statusline", targets: ["wiggleroom-statusline"]),
    ],
    targets: [
        .target(name: "WiggleroomCore"),
        .target(name: "WiggleroomUI", dependencies: ["WiggleroomCore"]),
        .target(name: "WiggleroomWindows", dependencies: ["WiggleroomCore", "WiggleroomUI"]),
        .executableTarget(name: "wiggleroom-statusline", dependencies: ["WiggleroomCore"]),
        .testTarget(
            name: "WiggleroomCoreTests",
            dependencies: ["WiggleroomCore"],
            exclude: ["Fixtures"]
        ),
        // Lays out every window and the popover at its real size and fails if anything is cut off.
        .testTarget(name: "WindowLayoutTests", dependencies: ["WiggleroomCore", "WiggleroomUI", "WiggleroomWindows"]),
        // Runs the real wiggleroom-statusline binary as Claude Code would.
        .testTarget(name: "StatuslineTests", dependencies: ["WiggleroomCore", "wiggleroom-statusline"]),
    ]
)
