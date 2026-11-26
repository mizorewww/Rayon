//
//  SSHStatusLineTests.swift
//  RayonModuleTests
//
//  The terminal's sign-in status lines name the user sshd sees.
//

@testable import RayonModule
import os
import XCTest

final class SSHStatusLineTests: XCTestCase {
    func testStatusLinesNameTheServersUsernameOverride() async throws {
        var machine = RDMachine(remoteAddress: "127.0.0.1", remotePort: "1", name: "closed")
        machine.sshUsername = " qa "
        let identity = RDIdentity(username: "deploy", password: "secret")
        let lines = OSAllocatedUnfairLock(initialState: [String]())
        do {
            _ = try await machine.connectSSH(identity: identity, autoIdentities: [], timeout: .seconds(2)) { line in
                lines.withLock { $0.append(line) }
            }
            XCTFail("nothing listens on port 1")
        } catch let failure as RDMachine.SSHFailure {
            XCTAssertTrue(failure.unreachable)
        }
        XCTAssertEqual(lines.withLock { $0 }, ["[i] Signing in as qa with \(identity.getKeyType())"])
    }
}
