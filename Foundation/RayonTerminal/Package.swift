// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RayonTerminal",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "RayonTerminal", targets: ["RayonTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "2.2.2026100703"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
    ],
    targets: [
        .target(
            name: "RayonTerminal",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
                .product(name: "RayonDesign", package: "RayonDesign"),
            ]
        ),
        .testTarget(name: "RayonTerminalTests", dependencies: ["RayonTerminal"]),
    ]
)
