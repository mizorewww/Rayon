// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RayonDesign",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "RayonDesign",
            targets: ["RayonDesign"]
        ),
    ],
    targets: [
        .target(
            name: "RayonDesign",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
