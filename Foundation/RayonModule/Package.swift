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
        // so we can save disk space for menubar app
//        .library(
//            name: "RayonModule-Framework",
//            type: .dynamic,
//            targets: ["RayonModule"]
//        ),
    ],
    dependencies: [
        .package(name: "PropertyWrapper", path: "../PropertyWrapper"),
        .package(name: "NSRemoteShell", path: "../../External/NSRemoteShell"),
        .package(name: "Keychain", path: "../Keychain"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
    ],
    targets: [
        .target(
            name: "RayonModule",
            dependencies: [
                "PropertyWrapper",
                "NSRemoteShell",
                "Keychain",
                "RayonDesign",
            ]
        ),
        .testTarget(
            name: "RayonModuleTests",
            dependencies: ["RayonModule"]
        ),
    ]
)
