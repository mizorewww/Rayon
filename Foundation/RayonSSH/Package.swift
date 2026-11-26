// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RayonSSH",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "RayonSSH", targets: ["RayonSSH"]),
    ],
    dependencies: [
        // 0.12.1 moved its swift-nio-ssh pin to an unvetted third-party fork;
        // 0.12.0 still pins the Citadel author's own.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.0"),
        .package(url: "https://github.com/Joannis/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.12.3" ..< "4.0.0"),
    ],
    targets: [
        .target(
            name: "RayonSSH",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
    ]
)
