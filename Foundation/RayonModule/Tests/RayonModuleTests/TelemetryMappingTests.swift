//
//  TelemetryMappingTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class TelemetryMappingTests: XCTestCase {
    func testTransportFailuresMapToTheirCause() {
        typealias Outcome = TelemetryReport.ConnectionOutcome
        XCTAssertEqual(Outcome(.refused), .refused)
        XCTAssertEqual(Outcome(.hostNotFound), .dnsFailed)
        XCTAssertEqual(Outcome(.timedOut), .timeout)
        XCTAssertEqual(Outcome(.closed), .other)
        XCTAssertEqual(Outcome(.other), .other)
    }

    func testIdentitiesNameTheirMethodAndKeyType() {
        var identity = RDIdentity()
        identity.password = "secret"
        XCTAssertEqual(identity.telemetryAuthMethod, .password)
        XCTAssertNil(identity.telemetryKeyType)
        identity.privateKey = "-----BEGIN OPENSSH PRIVATE KEY-----"
        identity.publicKey = "ssh-ed25519 AAAAC3Nza comment"
        XCTAssertEqual(identity.telemetryAuthMethod, .publicKey)
        XCTAssertEqual(identity.telemetryKeyType, .ed25519)
        identity.publicKey = "ecdsa-sha2-nistp256 AAAA"
        XCTAssertEqual(identity.telemetryKeyType, .ecdsa)
        identity.useSSHAgent = true
        XCTAssertEqual(identity.telemetryAuthMethod, .agent)
    }
}

final class ConnectionOutcomeTests: XCTestCase {
    /// A refused port is counted as refused because of the error's type,
    /// whatever the message says.
    func testARefusedPortCountsAsRefused() async throws {
        let machine = RDMachine(remoteAddress: "127.0.0.1", remotePort: "1", name: "closed")
        do {
            _ = try await machine.connectSSH(identity: nil, autoIdentities: [], timeout: .seconds(2))
            XCTFail("connected to a closed port")
        } catch let failure as RDMachine.SSHFailure {
            XCTAssertTrue(failure.unreachable)
            XCTAssertEqual(failure.outcome, .refused)
        }
    }
}
