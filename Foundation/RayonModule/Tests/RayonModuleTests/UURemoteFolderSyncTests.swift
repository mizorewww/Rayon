//
//  UURemoteFolderSyncTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class UURemoteFolderSyncTests: XCTestCase {
    private func device(_ id: String, _ alias: String, platform: Int = 4) -> UUDeviceInfo {
        var device = UUDeviceInfo()
        device.deviceID = id
        device.alias = alias
        device.platform = platform
        device.status = "CONNECTED"
        return device
    }

    private let folder = UUID()

    /// Applies the changes the way the store does.
    private func apply(_ devices: [UUDeviceInfo], ownDeviceID: String = "", to machines: inout [RDMachine]) {
        let changes = UURemoteFolderSync.changes(devices: devices, folder: folder, ownDeviceID: ownDeviceID, machines: machines)
        for machine in changes.save {
            if let index = machines.firstIndex(where: { $0.id == machine.id }) {
                machines[index] = machine
            } else {
                machines.append(machine)
            }
        }
        machines.removeAll { changes.delete.contains($0.id) }
    }

    func testDesktopDevicesBecomeServersInTheFolder() {
        var machines: [RDMachine] = []
        apply([device("d1", "Mac"), device("p1", "Phone", platform: 2)], to: &machines)
        XCTAssertEqual(machines.map(\.name), ["Mac"])
        XCTAssertEqual(machines.first?.folderId, folder)
        XCTAssertEqual(machines.first?.remoteDesktopProtocol, .uuRemote)
    }

    func testRenamedDevicesRenameUntouchedServersOnly() {
        var machines: [RDMachine] = []
        apply([device("d1", "Mac"), device("d2", "PC")], to: &machines)
        let index = machines.firstIndex { $0.uuDeviceID == "d2" }!
        machines[index].name = "Gaming rig"
        apply([device("d1", "Mac mini"), device("d2", "PC 2")], to: &machines)
        XCTAssertEqual(Set(machines.map(\.name)), ["Mac mini", "Gaming rig"])
    }

    func testDevicesLeavingTheAccountLeaveTheFolder() {
        var machines: [RDMachine] = []
        apply([device("d1", "Mac"), device("d2", "PC")], to: &machines)
        // One moved out by the user stays wherever it is.
        let index = machines.firstIndex { $0.uuDeviceID == "d2" }!
        machines[index].folderId = UUID()
        apply([], to: &machines)
        XCTAssertEqual(machines.map(\.uuDeviceID), ["d2"])
    }

    func testRayonItselfIsNotAServer() {
        var machines: [RDMachine] = []
        apply([device("me", "Rayon", platform: 1), device("d1", "Mac")], ownDeviceID: "me", to: &machines)
        XCTAssertEqual(machines.map(\.uuDeviceID), ["d1"])
    }

    func testOnlyUUServersAreUUDevices() {
        var ssh = RDMachine(remoteAddress: "10.0.0.2", remotePort: "22", name: "box")
        ssh.remoteDesktopProtocol = .uuRemote
        ssh.uuDeviceID = "d1"
        XCTAssertFalse(ssh.isUURemoteDevice)
        XCTAssertTrue(UURemoteFolderSync.makeMachine(for: device("d1", "Mac"), folder: folder).isUURemoteDevice)
    }

    /// A sign-in of Rayon is no computer: it never becomes a server.
    func testRayonSignInsAreNotDesktops() {
        var signIn = device("c1", "Rayon", platform: 1)
        signIn.versionName = UUConstants.versionName
        var pc = device("d1", "Rayon-lab-pc", platform: 1)
        pc.versionName = "4.44.0.3919"
        var machines: [RDMachine] = []
        apply([signIn, pc], to: &machines)
        XCTAssertEqual(machines.map(\.uuDeviceID), ["d1"])
    }

    func testEveryDeviceGivesADevicesServerTheSameID() {
        var mac: [RDMachine] = [], pad: [RDMachine] = []
        apply([device("d1", "Mac")], to: &mac)
        apply([device("d1", "Mac")], to: &pad)
        XCTAssertEqual(mac.map(\.id), pad.map(\.id))
        XCTAssertEqual(mac.first?.id, UURemoteFolderSync.machineID(for: "d1"))
    }
}
