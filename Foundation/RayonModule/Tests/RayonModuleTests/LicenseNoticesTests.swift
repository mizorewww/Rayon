//
//  LicenseNoticesTests.swift
//  RayonModuleTests
//
//  The About pages' libraries, read off the repository's LICENSE.
//

@testable import RayonModule
import XCTest

final class LicenseNoticesTests: XCTestCase {
    func testEachPlatformListsTheLibrariesItShips() throws {
        let license = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/LICENSE")
        let text = try String(contentsOf: license, encoding: .utf8)
        let mac = LicenseNotices.libraries(in: text, for: .macOS)
        let iOS = LicenseNotices.libraries(in: text, for: .iOS)
        let both = ["Citadel", "SwiftNIO SSH", "SwiftNIO", "GhosttyKit / GhosttyTerminal", "WCDB", "UURemoteKit", "WebRTC", "SwiftProtobuf", "BigInt", "Swift Collections"]
        for shipped in both + ["CodeEditSourceEditor", "CodeEditTextView", "SwiftTreeSitter", "tree-sitter"] {
            XCTAssertTrue(mac.contains(shipped), "\(shipped) in \(mac)")
        }
        for shipped in both + ["Runestone.xcframework"] {
            XCTAssertTrue(iOS.contains(shipped), "\(shipped) in \(iOS)")
        }
        XCTAssertFalse(mac.contains("Runestone.xcframework"), "\(mac)")
        XCTAssertFalse(iOS.contains { $0.hasPrefix("CodeEdit") || $0 == "tree-sitter" }, "\(iOS)")
        // Runestone and its grammars are inside Runestone.xcframework;
        // SwiftLint never ships; libssh2 and OpenSSL left with NSRemoteShell.
        for absent in ["Runestone", "TreeSitterLanguages", "tree-sitter-bash", "SwiftLintPlugin", "* Footnote", "libssh2", "OpenSSL"] {
            XCTAssertFalse(mac.contains(absent) || iOS.contains(absent), "\(absent) in \(mac) / \(iOS)")
        }
        // A NOTICE's own dividers do not start a library.
        XCTAssertFalse((mac + iOS).contains { $0.hasPrefix("This product") || $0.hasPrefix("Please visit") }, "\(mac)")
    }
}
