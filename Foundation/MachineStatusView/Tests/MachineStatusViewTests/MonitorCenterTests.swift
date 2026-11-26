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
        edited.comment = "edge"
        edited.ghosttyTerminfoVersion = "1.2"
        edited.fileTransferLoginPath = "/srv"
        edited.remoteDesktopProtocol = .vnc
        edited.vncPort = "5901"
        edited.vncUsername = "viewer"
        edited.vncPassword = "vnc"
        edited.vncShared = false
        edited.vncOverSSH = true
        edited.uuDeviceAlias = "office"
        edited.uuDisplayID = 1
        edited.uuFPS = 30
        edited.uuQuality = 3
        edited.uuTrueColor = true
        edited.uuManaged = true
        var used = identity
        used.lastRecentUsed = Date()
        used.comment = "laptop"
        used.group = "ops"
        used.authenticAutomatically = false
        XCTAssertFalse(MonitorCenter.connectsDifferently(machine, identity, edited, used))
    }

    func testANewAddressPortUserOrIdentityReconnects() {
        for edit: (inout RDMachine) -> Void in [
            { $0.remoteAddress = "192.0.2.2" },
            { $0.remotePort = "2222" },
            { $0.sshUsername = "admin" },
            { $0.associatedIdentity = UUID() },
            { $0.transport = .cloudflareAccess },
            { $0.cloudflareServiceTokenID = "token" },
            { $0.cloudflareServiceTokenSecret = "secret" },
            { $0.proxyJumpMachineID = UUID() },
            { $0.uuDeviceID = "device" },
        ] {
            var edited = machine
            edit(&edited)
            XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, edited, identity))
        }
        var rekeyed = identity
        rekeyed.password = "changed"
        XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, machine, rekeyed))
        for edit: (inout RDIdentity) -> Void in [
            { $0.username = "admin" },
            { $0.privateKey = "key" },
            { $0.publicKey = "ssh-ed25519 AAAA" },
            { $0.useSSHAgent = true },
        ] {
            var edited = identity
            edit(&edited)
            XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, machine, edited))
        }
        XCTAssertTrue(MonitorCenter.connectsDifferently(machine, identity, machine, nil))
    }
}

final class MonitorEmptyRoundTests: XCTestCase {
    func testAServerThatNeverAnsweredIsUnavailableNotDead() {
        // Windows OpenSSH: connected, but /bin/sh never runs the script.
        XCTAssertFalse(MonitorSession.emptyRoundIsDeadLink(hasReading: false, linkAnswers: true))
    }

    func testAnEmptyRoundAfterAReadingIsADeadLink() {
        XCTAssertTrue(MonitorSession.emptyRoundIsDeadLink(hasReading: true, linkAnswers: true))
    }

    func testAServerThatRunsNothingIsOutOfReach() {
        // Paused, or a link that has not noticed it dropped.
        XCTAssertTrue(MonitorSession.emptyRoundIsDeadLink(hasReading: false, linkAnswers: false))
    }
}
