// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RayonTerminal",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "RayonTerminal", targets: ["RayonTerminal"]),
        .executable(name: "RayonConfigurationPreview", targets: ["RayonConfigurationPreview"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "2.2.2026100703"),
        .package(url: "https://github.com/Lakr233/BlossomColorPicker.git", exact: "1.0.0"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
    ],
    targets: [
        .target(
            name: "RayonTerminal",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
                .product(name: "BlossomColorPicker", package: "BlossomColorPicker"),
                .product(name: "RayonDesign", package: "RayonDesign"),
            ],
            resources: [.process("Configuration/Resources")]
        ),
        .testTarget(name: "RayonTerminalTests", dependencies: ["RayonTerminal"]),
        .executableTarget(name: "RayonConfigurationPreview", dependencies: ["RayonTerminal"]),
    ]
)
