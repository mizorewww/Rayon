//
//  RemoteDesktopSessionTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

@MainActor
final class RemoteDesktopSessionTests: XCTestCase {
    /// A VNC password corrected and saved after the page opened is the one
    /// Reconnect sends, not the one the session opened with.
    func testReconnectUsesTheServerAsSavedNow() throws {
        let test = try TestStorage()
        let store = test.store()
        var machine = RDMachine(remoteAddress: "127.0.0.1", remotePort: "22", name: "desktop")
        machine.vncPassword = "wrong"
        XCTAssertTrue(store.save(machine))
        // No protocol: connecting rereads the server, then stops before
        // anything goes over the network.
        let session = RemoteDesktopSession(machine: machine, protocolType: .none, store: store)
        machine.vncPassword = "corrected"
        machine.uuFPS = 30
        XCTAssertTrue(store.save(machine))
        XCTAssertEqual(session.machine.vncPassword, "wrong")

        session.connect()
        XCTAssertEqual(session.machine.vncPassword, "corrected")
        XCTAssertEqual(session.streamSettings, RemoteDesktopStreamSettings(machine: machine))
        session.disconnect()
    }
}
