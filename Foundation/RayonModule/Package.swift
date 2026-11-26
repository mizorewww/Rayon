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
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
        .package(name: "Keychain", path: "../Keychain"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
        .package(name: "RayonEditor", path: "../RayonEditor"),
        .package(name: "RayonTerminal", path: "../RayonTerminal"),
        .package(url: "https://github.com/mizorewww/UURemoteKit.git", from: "0.1.2"),
    ],
    targets: [
        .target(
            name: "RayonModule",
            dependencies: [
                "NSRemoteShell",
                .product(name: "BigInt", package: "BigInt"),
                "Keychain",
                "RayonDesign",
                "RayonEditor",
                "RayonTerminal",
                "UURemoteKit",
            ]
        ),
        .testTarget(
            name: "RayonModuleTests",
            dependencies: [
                "RayonModule",
                .product(name: "BigInt", package: "BigInt"),
            ]
        ),
    ]
)
