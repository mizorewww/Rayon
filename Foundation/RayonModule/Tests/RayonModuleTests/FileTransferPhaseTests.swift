//
//  FileTransferPhaseTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class FileTransferPhaseTests: XCTestCase {
    private func makeContext() -> FileTransferContext {
        // The store must be born on the main thread; the context's
        // background bootstrap would otherwise race to create it.
        _ = RayonStore.shared
        return FileTransferContext(
            machine: RDMachine(
                remoteAddress: "10.0.0.1",
                remotePort: "22",
                name: "alpha",
                group: "",
                associatedIdentity: nil
            )
        )
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
