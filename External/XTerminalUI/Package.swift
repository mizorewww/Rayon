// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XTerminalUI",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "XTerminalUI",
            targets: ["XTerminalUI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "XTerminalUI",
            dependencies: [],
            resources: [.copy("xterm")]
        ),
    ]
)
