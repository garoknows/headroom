// swift-tools-version:6.0
import PackageDescription

// HeadroomCore: everything that can be tested without a Mac app around it.
//  - HeadroomCore: parsing Claude Code's status line JSON, the snapshot file, display text,
//    alerts and the Claude Code settings editor. Foundation only.
//  - HeadroomUI: the SwiftUI cards shared by the widget, the menu bar popover and the renders.
//  - headroom-statusline: the tiny command Claude Code runs on every update.
let package = Package(
    name: "HeadroomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HeadroomCore", targets: ["HeadroomCore"]),
        .library(name: "HeadroomUI", targets: ["HeadroomUI"]),
        .executable(name: "headroom-statusline", targets: ["headroom-statusline"]),
    ],
    targets: [
        .target(name: "HeadroomCore"),
        .target(name: "HeadroomUI", dependencies: ["HeadroomCore"]),
        .executableTarget(name: "headroom-statusline", dependencies: ["HeadroomCore"]),
        .testTarget(
            name: "HeadroomCoreTests",
            dependencies: ["HeadroomCore"],
            exclude: ["Fixtures"]
        ),
        // Runs the real headroom-statusline binary as Claude Code would.
        .testTarget(name: "StatuslineTests", dependencies: ["HeadroomCore", "headroom-statusline"]),
    ]
)
