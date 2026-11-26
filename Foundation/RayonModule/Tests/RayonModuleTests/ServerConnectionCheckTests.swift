//
//  ServerConnectionCheckTests.swift
//  RayonModuleTests
//
//  "Add and Connect" awaits the check from the main actor.
//

@testable import RayonModule
import XCTest

final class ServerConnectionCheckTests: XCTestCase {
    @MainActor
    func testAClosedPortIsUnreachable() async throws {
        // Port 1 on the loopback refuses at once.
        let draft = RDMachine(remoteAddress: "127.0.0.1", remotePort: "1")
        let outcome = await ServerConnectionCheck.run(draft, identity: RDIdentity(username: "root", password: "pw"), candidates: [], timeout: 5)
        guard case .unreachable = outcome else {
            return XCTFail("expected unreachable")
        }
    }

    /// With no identity to try, a dead port still reads as a connection
    /// failure, not as identities that could not sign in.
    @MainActor
    func testAClosedPortIsUnreachableWithNoIdentities() async throws {
        let draft = RDMachine(remoteAddress: "127.0.0.1", remotePort: "1")
        let outcome = await ServerConnectionCheck.run(draft, identity: nil, candidates: [], timeout: 5)
        guard case let .unreachable(reason) = outcome else {
            return XCTFail("expected unreachable, got \(outcome)")
        }
        XCTAssertEqual(reason, "Unable to connect to 127.0.0.1:1 (connection refused; nothing is listening on that port).")
    }

    /// An identity with neither password nor key never reaches the
    /// server; a dead port is still reported as such.
    @MainActor
    func testAClosedPortIsUnreachableWhenNoIdentityHasCredentials() async throws {
        let draft = RDMachine(remoteAddress: "127.0.0.1", remotePort: "1")
        let outcome = await ServerConnectionCheck.run(draft, identity: nil, candidates: [RDIdentity(username: "root")], timeout: 5)
        guard case .unreachable = outcome else {
            return XCTFail("expected unreachable, got \(outcome)")
        }
    }
}
