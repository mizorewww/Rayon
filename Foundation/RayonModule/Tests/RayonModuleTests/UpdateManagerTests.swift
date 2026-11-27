//
//  UpdateManagerTests.swift
//  RayonModuleTests
//
//  The update check reads a release against the running version; no test
//  contacts GitHub.
//

@testable import RayonModule
import XCTest

final class UpdateManagerTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            htmlURL: URL(string: "https://github.com/mizorewww/Rayon/releases/tag/\(tag)")!,
            draft: draft,
            prerelease: prerelease
        )
    }

    func testANewerTagIsAnUpdateWithItsReleasePage() {
        let package = UpdateManager.update(from: release("v2.9"), over: "2.8")
        XCTAssertEqual(package?.version, "2.9")
        XCTAssertEqual(package?.downloadURL.absoluteString, "https://github.com/mizorewww/Rayon/releases/tag/v2.9")
    }

    func testVersionsCompareByNumberNotByText() {
        XCTAssertNotNil(UpdateManager.update(from: release("v2.10"), over: "2.9"))
        XCTAssertNotNil(UpdateManager.update(from: release("v2.8.1"), over: "2.8"))
        XCTAssertNotNil(UpdateManager.update(from: release("3.0"), over: "2.8"))
    }

    func testTheSameOrAnOlderTagIsNoUpdate() {
        XCTAssertNil(UpdateManager.update(from: release("v2.8"), over: "2.8"))
        XCTAssertNil(UpdateManager.update(from: release("v2.7"), over: "2.8"))
        XCTAssertNil(UpdateManager.update(from: release("v2.8"), over: "2.8.1"))
    }

    func testDraftsAndPrereleasesAreNoUpdate() {
        XCTAssertNil(UpdateManager.update(from: release("v9.0", draft: true), over: "2.8"))
        XCTAssertNil(UpdateManager.update(from: release("v9.0", prerelease: true), over: "2.8"))
    }

    func testGitHubsReleaseJSONDecodes() throws {
        let json = Data(#"{"tag_name":"v2.8","html_url":"https://github.com/mizorewww/Rayon/releases/tag/v2.8","draft":false,"prerelease":false,"body":"notes"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(GitHubRelease.self, from: json), release("v2.8"))
    }

    func testAnAppleBuildNeverAsksGitHub() async throws {
        let newer = release("v9.0")
        let manager = UpdateManager(channel: .fromApple, currentVersion: "2.8") {
            XCTFail("an App Store build must not fetch releases")
            return newer
        }
        XCTAssertFalse(manager.canCheckForUpdates)
        let package = try await manager.availableUpdate()
        XCTAssertNil(package)
    }

    func testAGitHubBuildReportsTheFetchedRelease() async throws {
        let latest = release("v2.9")
        let manager = UpdateManager(channel: .fromGitHub, currentVersion: "2.8") { latest }
        let package = try await manager.availableUpdate()
        XCTAssertEqual(package?.version, "2.9")
    }
}
