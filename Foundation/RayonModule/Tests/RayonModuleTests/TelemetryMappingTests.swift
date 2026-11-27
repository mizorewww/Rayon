//
//  TelemetryMappingTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class TelemetryMappingTests: XCTestCase {
    func testTransportFailuresMapToTheirCause() {
        typealias Outcome = TelemetryReport.ConnectionOutcome
        XCTAssertEqual(Outcome(reason: "Unable to connect to db.example.com:22 (connection refused; nothing is listening on that port)."), .refused)
        XCTAssertEqual(Outcome(reason: "Unable to connect to nowhere.invalid:22 (the host name could not be found)."), .dnsFailed)
        XCTAssertEqual(Outcome(reason: "Unable to connect to 10.0.0.1:22 (the server did not answer in time)."), .timeout)
        XCTAssertEqual(Outcome(reason: "Timed out signing in to 10.0.0.1."), .timeout)
        XCTAssertEqual(Outcome(reason: "the server reset the connection"), .other)
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
