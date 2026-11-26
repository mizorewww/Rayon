//
//  SSHConnectionPoolTests.swift
//  RayonModuleTests
//
//  A pooled connection is keyed by what it signed in with.
//

@testable import RayonModule
import XCTest

final class SSHConnectionPoolTests: XCTestCase {
    func testChangedSecretsChangeTheKey() {
        let identity = RDIdentity(username: "deploy", password: "old")
        let same = SSHConnectionPool.secretsFingerprint([], [identity])
        XCTAssertEqual(same, SSHConnectionPool.secretsFingerprint([], [identity]))
        XCTAssertFalse(same.contains("old"))

        var changed = identity
        changed.password = "new"
        XCTAssertNotEqual(same, SSHConnectionPool.secretsFingerprint([], [changed]))
        changed = identity
        changed.privateKey = "-----BEGIN OPENSSH PRIVATE KEY-----"
        XCTAssertNotEqual(same, SSHConnectionPool.secretsFingerprint([], [changed]))
        XCTAssertNotEqual(same, SSHConnectionPool.secretsFingerprint(["token-secret"], [identity]))
        // Fields are delimited: moving a character between two is a change.
        XCTAssertNotEqual(
            SSHConnectionPool.secretsFingerprint(["ab", "c"], []),
            SSHConnectionPool.secretsFingerprint(["a", "bc"], [])
        )
    }
}
