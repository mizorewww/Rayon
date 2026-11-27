//
//  LibraryNoticeTests.swift
//  RayonModuleTests
//
//  The About pages' libraries, read off the repository's Libraries.json.
//

@testable import RayonModule
import XCTest

final class LibraryNoticeTests: XCTestCase {
    func testEachPlatformListsTheLibrariesItShips() throws {
        let json = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Libraries.json")
        let data = try Data(contentsOf: json)
        let mac = try LibraryNotice.shipped(in: data, on: "macOS")
        let iOS = try LibraryNotice.shipped(in: data, on: "iOS")
        let macNames = mac.map(\.name), iOSNames = iOS.map(\.name)
        let both = ["Rayon", "Citadel", "SwiftNIO SSH", "SwiftNIO", "GhosttyKit / GhosttyTerminal / GhosttyTheme", "BlossomColorPicker", "WCDB", "UURemoteKit", "WebRTC", "SwiftProtobuf", "BigInt", "DpkgVersion", "Swift Collections", "tree-sitter"]
        for shipped in both + ["CodeEditSourceEditor", "CodeEditTextView", "SwiftTreeSitter"] {
            XCTAssertTrue(macNames.contains(shipped), "\(shipped) in \(macNames)")
        }
        for shipped in both + ["Runestone.xcframework", "Runestone", "TreeSitterLanguages", "tree-sitter-bash"] {
            XCTAssertTrue(iOSNames.contains(shipped), "\(shipped) in \(iOSNames)")
        }
        XCTAssertFalse(macNames.contains { $0.hasPrefix("Runestone") || $0 == "TreeSitterLanguages" }, "\(macNames)")
        XCTAssertFalse(iOSNames.contains { $0.hasPrefix("CodeEdit") }, "\(iOSNames)")
        // SwiftLint never ships; the footnote is no library.
        XCTAssertFalse((macNames + iOSNames).contains { $0 == "SwiftLintPlugin" || $0.hasPrefix("*") })
        XCTAssertEqual(macNames, macNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        let rayon = try XCTUnwrap(mac.first { $0.name == "Rayon" })
        XCTAssertEqual(rayon.repository, "mizorewww/Rayon")
        XCTAssertEqual(rayon.url, URL(string: "https://github.com/mizorewww/Rayon"))
        XCTAssertEqual(rayon.license, "MIT")
        XCTAssertTrue(rayon.text.hasPrefix("MIT License"))
        XCTAssertEqual(mac.first { $0.name == "SwiftNIO" }?.license, "Apache-2.0")
        XCTAssertEqual(mac.first { $0.name == "WCDB" }?.license, "BSD-3-Clause, MIT")
    }
}
