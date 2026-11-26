// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RayonModule",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "RayonModule",
            type: .static,
            targets: ["RayonModule"]
        ),
    ],
    dependencies: [
        .package(name: "RayonSSH", path: "../RayonSSH"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
        .package(url: "https://github.com/Lakr233/wcdb.xcframework", from: "2.1.26102501"),
        .package(url: "https://github.com/marksands/BetterCodable", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
        .package(name: "RayonEditor", path: "../RayonEditor"),
        .package(name: "RayonTerminal", path: "../RayonTerminal"),
        .package(url: "https://github.com/mizorewww/UURemoteKit.git", from: "0.1.3"),
    ],
    targets: [
        .target(
            name: "RayonModule",
            dependencies: [
                "RayonSSH",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "WCDBSwift", package: "wcdb.xcframework"),
                .product(name: "BetterCodable", package: "BetterCodable"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
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
                "RayonSSH",
                .product(name: "BigInt", package: "BigInt"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
