// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RayonTerminal",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RayonTerminal", targets: ["RayonTerminal"]),
        .executable(name: "RayonConfigurationPreview", targets: ["RayonConfigurationPreview"]),
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
                .product(name: "RayonDesign", package: "RayonDesign"),
            ],
            resources: [.process("Configuration/Resources")]
        ),
        .testTarget(name: "RayonTerminalTests", dependencies: ["RayonTerminal"]),
        .executableTarget(name: "RayonConfigurationPreview", dependencies: ["RayonTerminal"]),
    ]
)
