//
//  SSHAgentIdentityTests.swift
//  RayonModuleTests
//
//  An SSH Agent identity signs in through the session's agent.
//

@testable import RayonModule
import RayonSSH
import XCTest

final class SSHAgentIdentityTests: XCTestCase {
    func testAnAgentIdentityUsesTheSessionsAgent() throws {
        var identity = RDIdentity(username: "deploy")
        identity.useSSHAgent = true
        // The process environment is left alone: Ghostty reads it on other threads.
        let credentials = try identity.sshCredentials(environment: ["SSH_AUTH_SOCK": "/tmp/rayon-test-agent.sock"])
        guard case let .agent(agent) = credentials.first, credentials.count == 1 else {
            return XCTFail("\(credentials)")
        }
        XCTAssertEqual(agent.socketPath, "/tmp/rayon-test-agent.sock")
        XCTAssertThrowsError(try identity.sshCredentials(environment: [:])) { error in
            XCTAssertTrue(error.localizedDescription.contains("SSH_AUTH_SOCK"), error.localizedDescription)
        }
    }

    /// A key is decrypted once per key and passphrase, not on every connect.
    func testAKeyIsDecryptedOnce() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-key-\(UUID().uuidString)").path
        let keygen = Process()
        keygen.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        keygen.arguments = ["-q", "-t", "ed25519", "-a", "64", "-N", "secret", "-f", path]
        try keygen.run()
        keygen.waitUntilExit()
        defer { try? FileManager.default.removeItem(atPath: path); try? FileManager.default.removeItem(atPath: path + ".pub") }
        var identity = RDIdentity(username: "deploy", password: "secret")
        identity.privateKey = try String(contentsOfFile: path, encoding: .utf8)

        let clock = ContinuousClock()
        let first = try clock.measure { _ = try identity.sshCredentials() }
        let again = try clock.measure { _ = try identity.sshCredentials() }
        XCTAssertLessThan(again * 10, first, "decrypted again")
        identity.password = "wrong"
        XCTAssertThrowsError(try identity.sshCredentials(), "a changed passphrase is tried")
    }
}
