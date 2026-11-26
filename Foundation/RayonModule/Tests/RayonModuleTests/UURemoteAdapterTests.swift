//
//  UURemoteAdapterTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class UURemoteAdapterTests: XCTestCase {
    func testAServerConnectsToItsDeviceOrItsShare() {
        var machine = RDMachine(remoteAddress: "address-id", name: "pc")
        XCTAssertEqual(machine.uuTarget, UURemoteTarget(deviceID: "address-id"))
        machine.uuDeviceID = "device-id"
        machine.uuAssistID = "share"
        machine.uuAssistCode = "1234"
        XCTAssertEqual(machine.uuTarget, UURemoteTarget(deviceID: "device-id", assistID: "share", assistCode: "1234"))
    }

    func testStreamSettingsAndScreensCarryOver() {
        let settings = RemoteDesktopStreamSettings(fps: 120, quality: 3, trueColor: true)
        XCTAssertEqual(RemoteDesktopStreamSettings(UUStreamSettings(settings)), settings)
        let screen = UUScreen(id: 2, name: "Side", width: 2560, height: 1440, fps: 144, isPrimary: false, isVirtual: true, videoTrackIndex: 1)
        XCTAssertEqual(RemoteDisplayInfo(screen), RemoteDisplayInfo(id: 2, name: "Side", width: 2560, height: 1440, fps: 144, isPrimary: false, isVirtual: true, videoTrackIndex: 1))
    }

    /// Rayon's own registrations on the account are no servers.
    func testTheFolderLeavesOutRayonsOwnDevices() {
        var own = UUDeviceInfo()
        own.deviceID = "own"
        own.alias = "Rayon · mini"
        own.platform = 1
        var host = UUDeviceInfo()
        host.deviceID = "host"
        host.alias = "Desk"
        host.platform = 4
        var group = RDMachineGroup()
        UURemoteFolderSync.apply(devices: [own, host], folder: "UU Remote", to: &group)
        XCTAssertEqual(group.machines.map(\.uuDeviceID), ["host"])
    }
}
