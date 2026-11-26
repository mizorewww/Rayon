//
//  SSHConnectionPoolTests.swift
//  RayonModuleTests
//
//  A pooled connection is keyed by what it signed in with.
//

import CryptoKit
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

    /// A digest anyone can recompute would let a guessed password be
    /// checked against the key.
    func testTheFingerprintIsNoPlainDigest() {
        let identity = RDIdentity(username: "deploy", password: "hunter2")
        var plain = SHA256()
        for value in [identity.id.uuidString, identity.username, identity.password, identity.privateKey, ""] {
            plain.update(data: Data(value.utf8))
            plain.update(data: Data([0]))
        }
        let digest = plain.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(SSHConnectionPool.secretsFingerprint([], [identity]), digest)
    }

    /// A jump host's password changing changes the key of the servers
    /// reached through it.
    @MainActor
    func testTheJumpHostsSecretsAreInTheKey() throws {
        let test = try TestStorage()
        let store = test.store()
        store.publishesWorkerSnapshot = true
        defer { RayonStore.workerSnapshot.withLock { $0 = WorkerSnapshot() } }
        var jumpIdentity = RDIdentity(username: "jump", password: "old")
        let targetIdentity = RDIdentity(username: "target", password: "pw")
        store.save(jumpIdentity)
        store.save(targetIdentity)
        let bastion = RDMachine(remoteAddress: "bastion", remotePort: "22", name: "bastion", associatedIdentity: jumpIdentity.id)
        store.save(bastion)
        var target = RDMachine(remoteAddress: "target", remotePort: "22", name: "target", associatedIdentity: targetIdentity.id)
        target.transport = .proxyJump
        target.proxyJumpMachineID = bastion.id
        store.save(target)

        let before = SSHConnectionPool.key(for: target)
        jumpIdentity.password = "new"
        store.save(jumpIdentity)
        XCTAssertNotEqual(SSHConnectionPool.key(for: target), before)
    }
}
