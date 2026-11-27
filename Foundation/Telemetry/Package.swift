// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Telemetry",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "Telemetry", targets: ["Telemetry"]),
    ],
    dependencies: [
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(name: "Telemetry", dependencies: ["Logger"]),
        .testTarget(name: "TelemetryTests", dependencies: ["Telemetry"], exclude: ["Fixtures"]),
    ]
)
