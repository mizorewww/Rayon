//
//  ServerUsernameTests.swift
//  RayonModuleTests
//
//  The SSH user name belongs to the server; the identity's applies only
//  when the server sets none.
//

@testable import RayonModule
import XCTest

@MainActor
final class ServerUsernameTests: XCTestCase {
    func testSSHUsernameSurvivesARoundTrip() throws {
        let test = try TestStorage()
        let machine = try test.storage.save(RDMachine(remoteAddress: "192.0.2.20", remotePort: "22", name: "web", sshUsername: "deploy"))
        XCTAssertEqual(test.storage.record(RDMachine.self, id: machine.id)?.sshUsername, "deploy")
    }

    func testTheServersUsernameOverridesTheIdentitys() {
        let identity = RDIdentity(username: "root", password: "secret")
        var machine = RDMachine(remoteAddress: "192.0.2.23", remotePort: "22")
        XCTAssertEqual(machine.sshLoginUsername(identity: identity), "root")
        XCTAssertEqual(identity.loginUsername(override: machine.sshUsernameOverride), "root")

        machine.sshUsername = "  deploy "
        XCTAssertEqual(machine.sshUsernameOverride, "deploy")
        XCTAssertEqual(machine.sshLoginUsername(identity: identity), "deploy")
        XCTAssertEqual(machine.sshLoginUsername(identity: nil), "deploy")
        XCTAssertEqual(identity.loginUsername(override: machine.sshUsernameOverride), "deploy")

        machine.sshUsername = "   "
        XCTAssertNil(machine.sshUsernameOverride)
        XCTAssertEqual(machine.sshLoginUsername(identity: nil), "")
    }

    func testImportSharesOneIdentityPerKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServerUsernameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sharedKey = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(UUID().uuidString)\n-----END OPENSSH PRIVATE KEY-----\n"
        let otherKey = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(UUID().uuidString)\n-----END OPENSSH PRIVATE KEY-----\n"
        try sharedKey.write(to: directory.appendingPathComponent("shared"), atomically: true, encoding: .utf8)
        try otherKey.write(to: directory.appendingPathComponent("other"), atomically: true, encoding: .utf8)

        let tag = UUID().uuidString.prefix(8)
        let config = """
        Host alpha-\(tag)
            HostName 192.0.2.30
            User root
            IdentityFile \(directory.path)/shared

        Host beta-\(tag)
            HostName 192.0.2.31
            User deploy
            IdentityFile \(directory.path)/shared

        Host gamma-\(tag)
            HostName 192.0.2.32
            User root
            IdentityFile \(directory.path)/other
        """

        let test = try TestStorage()
        let store = test.store()
        let result = store.importOpenSSHConfig(config)
        let machines = store.machines.filter { $0.name.hasSuffix("-\(tag)") }
        let identityIDs = Set(machines.compactMap(\.associatedIdentity))

        XCTAssertEqual(result.importedServers, 3)
        XCTAssertEqual(result.importedIdentities, 2)
        XCTAssertEqual(identityIDs.count, 2)

        let alpha = try XCTUnwrap(machines.first { $0.name == "alpha-\(tag)" })
        let beta = try XCTUnwrap(machines.first { $0.name == "beta-\(tag)" })
        let gamma = try XCTUnwrap(machines.first { $0.name == "gamma-\(tag)" })
        XCTAssertEqual(alpha.associatedIdentity, beta.associatedIdentity)
        XCTAssertNotEqual(alpha.associatedIdentity, gamma.associatedIdentity)
        XCTAssertEqual(alpha.sshUsername, "root")
        XCTAssertEqual(beta.sshUsername, "deploy")
        XCTAssertEqual(gamma.sshUsername, "root")

        let shared = try XCTUnwrap(store.associatedIdentity(for: beta))
        XCTAssertEqual(shared.privateKey, sharedKey)
        XCTAssertEqual(beta.sshLoginUsername(identity: shared), "deploy")
        XCTAssertEqual(alpha.sshLoginUsername(identity: shared), "root")
    }
}
