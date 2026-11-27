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
}
