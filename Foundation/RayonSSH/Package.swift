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
        // Citadel 0.12.0 (0.12.1 moved its swift-nio-ssh pin to an unvetted
        // third-party fork) with the login timeout left to the caller, a
        // sign-in that ends when its channel closes, listDirectory closing
        // the handle it opens, and an lstat.
        .package(url: "https://github.com/mizorewww/Citadel.git", revision: "d5c5e2365009392e8ff39b1a06c2821b5eba8184"),
        // Citadel's swift-nio-ssh fork (0.3.5) with apple/swift-nio-ssh#144
        // applied (data arriving on a channel this side has closed adjusted
        // the closed channel's window and trapped), and a child channel's
        // closeFuture never failing, as NIOAsyncChannel requires.
        .package(url: "https://github.com/mizorewww/swift-nio-ssh.git", revision: "c6282c05103042b5f904dd5cd40a7953829aa4a0"),
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
        .testTarget(
            name: "RayonSSHTests",
            dependencies: [
                "RayonSSH",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
