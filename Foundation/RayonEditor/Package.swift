// swift-tools-version: 5.9
import PackageDescription

/// The remote file editor: Runestone (prebuilt, with its Tree-sitter grammars) on iOS, native NSTextView with line numbers and syntax highlighting on macOS.
let package = Package(
    name: "RayonEditor",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "RayonEditor", targets: ["RayonEditor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/Runestone.xcframework", exact: "0.3.2"),
        .package(name: "RayonDesign", path: "../RayonDesign"),
    ],
    targets: [
        .target(
            name: "RayonEditor",
            dependencies: [
                .product(name: "RayonDesign", package: "RayonDesign"),
                .product(name: "RunestoneEditor", package: "Runestone.xcframework", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "RayonEditorTests", dependencies: ["RayonEditor"]),
    ]
)
