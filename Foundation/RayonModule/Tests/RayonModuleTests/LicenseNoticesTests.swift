//
//  LicenseNoticesTests.swift
//  RayonModuleTests
//
//  The About pages' libraries, read off the repository's LICENSE.
//

@testable import RayonModule
import XCTest

final class LicenseNoticesTests: XCTestCase {
    func testTheLibrariesAreTheShippedOnes() throws {
        let license = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/LICENSE")
        let names = LicenseNotices.libraries(in: try String(contentsOf: license, encoding: .utf8))
        for shipped in ["Citadel", "SwiftNIO SSH", "SwiftNIO", "CodeEditSourceEditor", "UURemoteKit", "WebRTC", "SwiftProtobuf", "BigInt", "Runestone.xcframework"] {
            XCTAssertTrue(names.contains(shipped), "\(shipped) in \(names)")
        }
        // Runestone itself is inside Runestone.xcframework; SwiftLint never
        // ships; libssh2 and OpenSSL left with NSRemoteShell.
        for absent in ["Runestone", "SwiftLintPlugin", "* Footnote", "libssh2", "OpenSSL"] {
            XCTAssertFalse(names.contains(absent), "\(absent) in \(names)")
        }
        // A NOTICE's own dividers do not start a library.
        XCTAssertFalse(names.contains { $0.hasPrefix("This product") || $0.hasPrefix("Please visit") }, "\(names)")
    }
}
