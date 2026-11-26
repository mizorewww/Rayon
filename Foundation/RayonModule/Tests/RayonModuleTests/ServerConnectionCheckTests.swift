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
}
