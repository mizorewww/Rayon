// swift-tools-version: 5.9
import PackageDescription

/// The remote file editor: a Tree-sitter code editor on both platforms,
/// Runestone on iOS and CodeEditSourceEditor on macOS.
let package = Package(
    name: "RayonEditor",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "RayonEditor", targets: ["RayonEditor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/Runestone.xcframework", exact: "0.3.2"),
        .package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor", exact: "0.15.2"),
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", exact: "0.1.20"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
    ],
    targets: [
        .target(
            name: "RayonEditor",
            dependencies: [
                .product(name: "RayonDesign", package: "RayonDesign"),
                .product(name: "RunestoneEditor", package: "Runestone.xcframework", condition: .when(platforms: [.iOS])),
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor", condition: .when(platforms: [.macOS])),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "RayonEditorTests",
            dependencies: [
                "RayonEditor",
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor", condition: .when(platforms: [.macOS])),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages", condition: .when(platforms: [.macOS])),
            ]
        ),
    ]
)
