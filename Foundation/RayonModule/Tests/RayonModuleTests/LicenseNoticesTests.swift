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
        for shipped in ["libssh2", "CodeEditSourceEditor", "UURemoteKit", "WebRTC", "SwiftProtobuf", "BigInt", "Runestone.xcframework"] {
            XCTAssertTrue(names.contains(shipped), "\(shipped) in \(names)")
        }
        // Runestone itself is inside Runestone.xcframework; SwiftLint never ships.
        for absent in ["Runestone", "SwiftLintPlugin", "* Footnote"] {
            XCTAssertFalse(names.contains(absent), "\(absent) in \(names)")
        }
    }
}
