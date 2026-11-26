// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RayonModule",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "RayonModule",
            type: .static,
            targets: ["RayonModule"]
        ),
    ],
    dependencies: [
        .package(name: "NSRemoteShell", path: "../../External/NSRemoteShell"),
        .package(name: "Keychain", path: "../Keychain"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
        .package(name: "RayonEditor", path: "../RayonEditor"),
        .package(name: "RayonTerminal", path: "../RayonTerminal"),
    ],
    targets: [
        .target(
            name: "RayonModule",
            dependencies: [
                "NSRemoteShell",
                "Keychain",
                "RayonDesign",
                "RayonEditor",
                "RayonTerminal",
            ]
        ),
        .testTarget(
            name: "RayonModuleTests",
            dependencies: ["RayonModule"]
        ),
    ]
)
