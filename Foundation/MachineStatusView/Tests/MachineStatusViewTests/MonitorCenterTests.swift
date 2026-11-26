//
//  MonitorCenterTests.swift
//  MachineStatusViewTests
//
//  When a running monitor must reconnect with a server's edited details.
//

@testable import MachineStatusView
import RayonModule
import XCTest

@MainActor
final class MonitorCenterTests: XCTestCase {
    private let machine = RDMachine(remoteAddress: "192.0.2.1", remotePort: "22", name: "web", associatedIdentity: UUID().uuidString)
    private let identity = RDIdentity(username: "root", password: "secret")

    func testWhatIsWrittenBackOrOnlyShownKeepsTheSession() {
        var edited = machine
        edited.name = "web-01"
        edited.lastBanner = "SSH-2.0-OpenSSH_9.9"
        edited.lastConnection = Date()
        var used = identity
        used.lastRecentUsed = Date()
        XCTAssertFalse(MonitorCenter.connectsDifferently(machine, identity, edited, used))
    }

    func testANewAddressPortUserOrIdentityReconnects() {
        for edit: (inout RDMachine) -> Void in [
            { $0.remoteAddress = "192.0.2.2" },
            { $0.remotePort = "2222" },
            { $0.sshUsername = "admin" },
            { $0.associatedIdentity = UUID().uuidString },
        ] {
            var edited = machine
            edit(&edited)
            XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, edited, identity))
        }
        var rekeyed = identity
        rekeyed.password = "changed"
        XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, machine, rekeyed))
        XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, machine, nil))
    }
}
