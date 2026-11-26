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
    private let machine = RDMachine(remoteAddress: "192.0.2.1", remotePort: "22", name: "web", associatedIdentity: UUID())
    private let identity = RDIdentity(username: "root", password: "secret")

    func testWhatIsWrittenBackOrOnlyShownKeepsTheSession() {
        var edited = machine
        edited.name = "web-01"
        edited.lastBanner = "SSH-2.0-OpenSSH_9.9"
        edited.lastConnection = Date()
        edited.folderId = UUID()
        edited.modified = Date().addingTimeInterval(60)
        var used = identity
        used.lastRecentUsed = Date()
        XCTAssertFalse(MonitorCenter.connectsDifferently(machine, identity, edited, used))
    }

    func testANewAddressPortUserOrIdentityReconnects() {
        for edit: (inout RDMachine) -> Void in [
            { $0.remoteAddress = "192.0.2.2" },
            { $0.remotePort = "2222" },
            { $0.sshUsername = "admin" },
            { $0.associatedIdentity = UUID() },
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

final class MonitorEmptyRoundTests: XCTestCase {
    func testAServerThatNeverAnsweredIsUnavailableNotDead() {
        // Windows OpenSSH: connected, but /bin/sh never runs the script.
        XCTAssertFalse(MonitorSession.emptyRoundIsDeadLink(hasReading: false, connectionActive: true))
    }

    func testAnEmptyRoundAfterAReadingOrADropIsADeadLink() {
        XCTAssertTrue(MonitorSession.emptyRoundIsDeadLink(hasReading: true, connectionActive: true))
        XCTAssertTrue(MonitorSession.emptyRoundIsDeadLink(hasReading: false, connectionActive: false))
    }
}
