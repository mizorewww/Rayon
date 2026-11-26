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
        let machine = RDMachine(remoteAddress: "192.0.2.20", remotePort: "22", name: "web", sshUsername: "deploy")
        let data = try PropertyListEncoder().encode(machine)
        let decoded = try PropertyListDecoder().decode(RDMachine.self, from: data)
        XCTAssertEqual(decoded.sshUsername, "deploy")
        XCTAssertEqual(decoded, machine)

        let json = try JSONDecoder().decode(RDMachine.self, from: JSONEncoder().encode(machine))
        XCTAssertEqual(json.sshUsername, "deploy")
    }

    func testAnEmptySSHUsernameIsNotWritten() throws {
        let machine = RDMachine(remoteAddress: "192.0.2.21", remotePort: "22", name: "plain")
        let data = try JSONEncoder().encode(machine)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["sshUsername"])
    }

    func testServersSavedBeforeTheFieldDecode() throws {
        let legacy: [String: Any] = [
            "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            "remoteAddress": "192.0.2.22",
            "remotePort": "22",
            "name": "old",
            "group": "",
            "lastConnection": Date(timeIntervalSince1970: 1_700_000_000),
            "lastBanner": "",
            "comment": "",
            "associatedIdentity": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            "attachment": [String: String](),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        let machine = try PropertyListDecoder().decode(RDMachine.self, from: data)
        XCTAssertEqual(machine.sshUsername, "")
        XCTAssertNil(machine.sshUsernameOverride)
        XCTAssertEqual(machine.associatedIdentity, "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
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

        let store = RayonStore()
        let result = store.importOpenSSHConfig(config)
        let machines = store.machineGroup.machines.filter { $0.name.hasSuffix("-\(tag)") }
        let identityIDs = Set(machines.compactMap(\.associatedIdentity))
        defer {
            for machine in machines { store.machineGroup.delete(machine.id) }
            for raw in identityIDs { if let id = UUID(uuidString: raw) { store.identityGroup.delete(id) } }
        }

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
