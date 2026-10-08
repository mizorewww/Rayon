//
//  GroupTypeTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class GroupTypeTests: XCTestCase {
    private func makeMachine(name: String, group: String = "") -> RDMachine {
        RDMachine(
            remoteAddress: "10.0.0.1",
            remotePort: "22",
            name: name,
            group: group,
            associatedIdentity: nil
        )
    }

    func testInsertReplacesSameID() {
        var group = RDMachineGroup()
        var machine = makeMachine(name: "alpha")
        group.insert(machine)
        machine.name = "beta"
        group.insert(machine)
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(group[machine.id].name, "beta")
    }

    func testDelete() {
        var group = RDMachineGroup()
        let machine = makeMachine(name: "alpha")
        group.insert(machine)
        group.delete(machine.id)
        XCTAssertEqual(group.count, 0)
    }

    func testSectionsAreSorted() {
        var group = RDMachineGroup()
        group.insert(makeMachine(name: "a", group: "zeta"))
        group.insert(makeMachine(name: "b", group: "alpha"))
        XCTAssertEqual(group.sections, ["alpha", "zeta"])
    }

    func testPortForwardGroupEqualityReflectsContent() {
        // Regression: RDPortForwardGroup used to compare only its stable
        // group id, so edits to a forward never registered as a change
        // and SwiftUI did not refresh.
        let forward = RDPortForward(
            forwardOrientation: .listenLocal,
            bindPort: 8080,
            targetHost: "127.0.0.1",
            targetPort: 80,
            usingMachine: nil
        )
        var a = RDPortForwardGroup()
        a.insert(forward)
        var b = a
        XCTAssertTrue(a == b)
        var edited = forward
        edited.bindPort = 9090
        b.insert(edited)
        XCTAssertFalse(a == b, "editing a forward must make the groups unequal")
    }
}
