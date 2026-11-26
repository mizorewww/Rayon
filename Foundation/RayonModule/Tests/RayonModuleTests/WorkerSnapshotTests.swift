//
//  WorkerSnapshotTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

/// The worker snapshot mirrors main-thread writes through the property
/// observers, so a worker queue can read without touching the main-thread
/// properties. Assertions are scoped to fresh ids: the store persists to
/// the test host's defaults, so absolute counts would leak between runs.
final class WorkerSnapshotTests: XCTestCase {
    func testWorkerSnapshotMirrorsMainThreadWrites() {
        let store = RayonStore()
        let machine = RDMachine(remoteAddress: "192.0.2.1", remotePort: "22", name: "worker-alpha")
        store.machineGroup.insert(machine)
        XCTAssertEqual(store.workerMachine(for: machine.id).name, "worker-alpha")

        var edited = machine
        edited.name = "worker-beta"
        store.machineGroup.insert(edited)
        XCTAssertEqual(store.workerMachine(for: machine.id).name, "worker-beta")

        store.machineGroup.delete(machine.id)
        XCTAssertFalse(store.workerMachine(for: machine.id).isNotPlaceholder())

        let identity = RDIdentity(username: "worker-root", password: "secret")
        store.identityGroup.insert(identity)
        XCTAssertTrue(store.workerIdentitiesForAutoAuth.contains(where: { $0.id == identity.id }))

        store.timeout = 9
        XCTAssertEqual(store.workerTimeoutNumber, NSNumber(value: 9))
        store.monitorInterval = 7
        XCTAssertEqual(store.workerMonitorInterval, 7)
        store.terminalFontSize = 21
        XCTAssertEqual(store.workerTerminalFontSize, 21)
    }

    func testWorkerAssociatedIdentityResolvesLikeTheMainThreadOne() {
        let store = RayonStore()
        let identity = RDIdentity(username: "worker-resolve", password: "secret")
        store.identityGroup.insert(identity)
        defer { store.identityGroup.delete(identity.id) }

        var machine = RDMachine(remoteAddress: "192.0.2.2", remotePort: "22", name: "bound")
        machine.associatedIdentity = identity.id.uuidString
        XCTAssertEqual(store.workerAssociatedIdentity(for: machine)?.id, identity.id)

        // Malformed references and placeholders resolve to nil, as the
        // main-thread lookup does.
        machine.associatedIdentity = "not-a-uuid"
        XCTAssertNil(store.workerAssociatedIdentity(for: machine))
        machine.associatedIdentity = UUID().uuidString
        XCTAssertNil(store.workerAssociatedIdentity(for: machine))
    }
}
