//
//  SSHConnectionPoolTests.swift
//  RayonModuleTests
//
//  A pooled connection is keyed by what it signed in with, and one that
//  is still connecting is shared, failure included.
//

import CryptoKit
import NIOCore
import NIOPosix
import os
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

    /// Leases taken while the first one connects share its outcome. One
    /// that failed was dropped by the first lease before the others had
    /// looked, and they connected (and asked about the host key) again.
    @MainActor
    func testLeasesWaitingOnAFailingConnectShareTheFailure() async throws {
        let accepted = OSAllocatedUnfairLock(initialState: 0)
        // Takes the connection and hangs up after a while, before SSH starts.
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                accepted.withLock { $0 += 1 }
                channel.eventLoop.scheduleTask(in: .milliseconds(500)) { channel.close(promise: nil) }
                return channel.eventLoop.makeSucceededVoidFuture()
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        defer { server.close(promise: nil) }

        let test = try TestStorage()
        let store = test.store()
        store.publishesWorkerSnapshot = true
        defer { RayonStore.workerSnapshot.withLock { $0 = WorkerSnapshot() } }
        let identity = RDIdentity(username: "nobody", password: "pw")
        store.save(identity)
        let machine = RDMachine(remoteAddress: "127.0.0.1", remotePort: "\(server.localAddress!.port!)", name: "flaky", associatedIdentity: identity.id)
        store.save(machine)

        let pool = SSHConnectionPool()
        // The first lease resumes first when it runs at a higher priority
        // (the terminal beside a background forward reconnecting).
        let first = Task(priority: .high) { try await pool.lease(for: machine) }
        try await Task.sleep(for: .milliseconds(200))
        let others = (0 ..< 3).map { _ in Task(priority: .low) { try await pool.lease(for: machine) } }
        for lease in [first] + others {
            do {
                _ = try await lease.value
                XCTFail("signed in to a server that hangs up")
            } catch {}
        }
        XCTAssertEqual(accepted.withLock { $0 }, 1, "leases waiting on the failed connect connected again")
    }
}
