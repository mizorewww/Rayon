// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "Logger", targets: ["Logger"]),
    ],
    targets: [
        .target(name: "Logger"),
        .testTarget(name: "LoggerTests", dependencies: ["Logger"]),
    ]
)
