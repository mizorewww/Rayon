//
//  SFTPSessionTests.swift
//  RayonSSHTests
//
//  SFTP against a server whose listings the test makes up.
//

import Foundation
@testable import RayonSSH
import XCTest

final class SFTPSessionTests: XCTestCase {
    private func withSFTP(
        _ tree: FixedTreeSFTP,
        _ body: (SFTPSession) async throws -> Void
    ) async throws {
        let server = try await TestSSHServer.start(sftp: tree)
        let connection = try await server.connect()
        let sftp = try await connection.openSFTP()
        do {
            try await body(sftp)
        } catch {
            await sftp.close()
            await connection.close()
            await server.stop()
            throw error
        }
        await sftp.close()
        await connection.close()
        await server.stop()
    }

    /// Each listing closes the folder it opened: OpenSSH's sftp-server
    /// holds a few hundred handles, so browsing for a while ran it out.
    func testAListingClosesItsFolder() async throws {
        let tree = FixedTreeSFTP(["/home": [("notes.txt", "hello")]])
        try await withSFTP(tree) { sftp in
            for _ in 0 ..< 20 {
                let entries = try await sftp.entries(at: "/home")
                XCTAssertEqual(entries.map(\.name), ["notes.txt"])
            }
            // Asked while the session is open: closing it frees them all.
            XCTAssertEqual(tree.openedFolders.count, 20)
            XCTAssertEqual(tree.openFolderHandles, 0, "listings left folder handles open")
        }
    }

    /// Deleting asks the server about the item itself (lstat): listing
    /// its parent to find it cost a listing of a folder that may be huge.
    func testDeletingAFolderDoesNotListItsParent() async throws {
        let tree = FixedTreeSFTP([
            "/home": [("sub", nil), ("other.txt", "x")],
            "/home/sub": [("a.txt", "a")],
        ])
        try await withSFTP(tree) { sftp in
            try await sftp.removeItem(at: "/home/sub") { _ in }
        }
        XCTAssertEqual(tree.openedFolders, ["/home/sub"])
        XCTAssertEqual(tree.removedPaths, ["/home/sub/a.txt", "/home/sub"])
    }

    /// A server's listing decides the names a download writes: one that
    /// lists "../escaped", "a/b" or "..\\0" (which URL reads as "..") must not reach outside the folder the
    /// download goes to (CVE-2019-6111).
    func testADownloadStaysInsideItsFolder() async throws {
        let tree = FixedTreeSFTP([
            "/srv": [("../escaped", "evil"), ("a/b", "evil"), ("", "evil"), ("..\u{0}", "evil"), ("a\u{1}b", "evil"), ("tab\t", "evil"), (".", nil), ("..", nil), ("kept.txt", "kept")],
        ])
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let destination = scratch.appendingPathComponent("srv")
        try await withSFTP(tree) { sftp in
            let names = try await sftp.entries(at: "/srv").map(\.name)
            XCTAssertEqual(names, ["kept.txt"])
            try await sftp.download("/srv", to: destination) { _ in }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("escaped").path), "wrote outside the folder")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), ["srv"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["kept.txt"])
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("kept.txt"), encoding: .utf8), "kept")
    }
}
