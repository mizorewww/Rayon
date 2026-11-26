// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MachineStatus",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v7),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "MachineStatus",
            targets: ["MachineStatus"]
        ),
    ],
    targets: [
        .target(
            name: "MachineStatus"
        ),
        .testTarget(
            name: "MachineStatusTests",
            dependencies: ["MachineStatus"]
        ),
    ]
)
