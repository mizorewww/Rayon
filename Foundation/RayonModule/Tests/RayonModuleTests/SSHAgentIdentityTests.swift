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
}
