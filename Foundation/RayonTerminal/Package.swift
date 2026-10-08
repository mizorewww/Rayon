// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RayonTerminal",
    platforms: [.macOS(.v13)],
    products: [.library(name: "RayonTerminal", targets: ["RayonTerminal"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "2.2.2026100703"),
    ],
    targets: [
        .target(
            name: "RayonTerminal",
            dependencies: [.product(name: "GhosttyTerminal", package: "libghostty-spm")]
        ),
        .testTarget(name: "RayonTerminalTests", dependencies: ["RayonTerminal"]),
    ]
)
