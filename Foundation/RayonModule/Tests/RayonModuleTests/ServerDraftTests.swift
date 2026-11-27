//
//  ServerDraftTests.swift
//  RayonModuleTests
//
//  Both server editors save through ServerDraft, so they refuse the same input.
//

@testable import RayonModule
import XCTest

final class ServerDraftTests: XCTestCase {
    private func draft(address: String = "192.0.2.1", port: String = "22") -> ServerDraft {
        var draft = ServerDraft()
        draft.address = address
        draft.port = port
        return draft
    }

    func testPortZeroAndOutOfRangeAreRefused() {
        for port in ["0", "00", "65536", "-1", "", "ssh", "2 2"] {
            XCTAssertEqual(draft(port: port).problem, .invalidPort, port)
        }
        for port in ["1", "22", "65535", " 22 "] {
            XCTAssertNil(draft(port: port).problem, port)
        }
    }

    func testAddressIsRequired() {
        XCTAssertEqual(draft(address: "   ").problem, .emptyAddress)
    }

    func testProxyJumpNeedsAJumpServer() {
        var draft = draft()
        draft.transport = .proxyJump
        XCTAssertEqual(draft.problem, .noJumpServer)
        draft.proxyJumpMachineID = UUID()
        XCTAssertNil(draft.problem)
    }

    func testVNCPortIsCheckedOnlyForVNC() {
        var draft = draft()
        draft.vncPort = "0"
        XCTAssertNil(draft.problem)
        draft.remoteDesktopProtocol = .vnc
        XCTAssertEqual(draft.problem, .invalidVNCPort)
        draft.vncPort = ""
        XCTAssertNil(draft.problem)
    }

    func testApplyTrimsAndKeepsFieldsTheEditorDoesNotShow() {
        var machine = RDMachine(remoteAddress: "old", remotePort: "22")
        machine.uuFPS = 30
        machine.lastBanner = "hello"
        var draft = ServerDraft(machine, folder: "")
        draft.address = " host.example "
        draft.port = " 2222 "
        draft.name = "  "
        draft.startFolder = ""
        draft.serviceTokenID = "id"
        let saved = draft.apply(to: machine, folderId: nil)
        XCTAssertEqual(saved.remoteAddress, "host.example")
        XCTAssertEqual(saved.remotePort, "2222")
        XCTAssertEqual(saved.name, "host.example")
        XCTAssertEqual(saved.fileTransferLoginPath, "/")
        XCTAssertEqual(saved.cloudflareServiceTokenID, "", "a token applies only to Cloudflare Access")
        XCTAssertEqual(saved.uuFPS, 30)
        XCTAssertEqual(saved.lastBanner, "hello")
        XCTAssertEqual(ServerDraft(saved, folder: "").apply(to: saved, folderId: nil), saved)
    }
}
