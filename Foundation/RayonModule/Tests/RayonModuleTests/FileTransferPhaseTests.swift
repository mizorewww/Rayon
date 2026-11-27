//
//  FileTransferPhaseTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

@MainActor
final class FileTransferPhaseTests: XCTestCase {
    private func makeContext() -> FileTransferContext {
        FileTransferContext(machine: RDMachine(remoteAddress: "10.0.0.1", remotePort: "22", name: "alpha"))
    }

    func testNewContextIsIdle() {
        XCTAssertEqual(makeContext().connectionPhase, .idle)
    }

    func testShutdownClosesThePhaseAndKeepsTheDisplayHint() {
        let context = makeContext()
        context.processShutdown()
        XCTAssertEqual(context.connectionPhase, .closed)
        XCTAssertFalse(context.connected)
        XCTAssertEqual(context.currentHint, "Connection Closed", "the hint stays as the display text")
    }
}
