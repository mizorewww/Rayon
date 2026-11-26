//
//  UURemoteFolderSync.swift
//  RayonModule
//
//  A UU Remote account's folder follows the account: every desktop device
//  is a server in it, renamed when the device is, and gone when the device
//  leaves the account. Servers the user made or moved out are left alone.
//
//  Every device signed in to the account makes these servers, so each
//  device's server for a UU device has an id worked out from the UU device
//  id: the same everywhere, iCloud sync keeps one of it.
//

import CryptoKit
import Foundation
import UURemoteKit

public enum UURemoteFolderSync {
    /// The id of the server for a UU device, the same on every device.
    public static func machineID(for deviceID: String) -> UUID {
        let hash = Array(SHA256.hash(data: Data("me.mizorewww.rayon.uu-device.\(deviceID)".utf8)))
        var bytes = Array(hash.prefix(16))
        // A name-based UUID (version 5 layout, RFC 4122 variant).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// A server for a device, in `folder`.
    public static func makeMachine(for device: UUDeviceInfo, folder: RDFolder.ID?) -> RDMachine {
        var machine = RDMachine(
            remoteAddress: device.deviceID,
            remotePort: "22",
            name: device.alias.isEmpty ? device.deviceID : device.alias,
            folderId: folder,
            comment: "\(UUDeviceInfo.platformName(device.platform)) device"
        )
        machine.remoteDesktopProtocol = .uuRemote
        machine.uuDeviceID = device.deviceID
        machine.uuDeviceAlias = device.alias
        machine.transport = .uuRemote
        machine.uuManaged = true
        machine.id = machineID(for: device.deviceID)
        return machine
    }

    /// The servers to save and to delete so that the ones in `folder`
    /// follow `devices`. `ownDeviceID` is the device Rayon signed in as,
    /// which is not a server.
    public static func changes(
        devices: [UUDeviceInfo],
        folder: RDFolder.ID,
        ownDeviceID: String = "",
        machines: [RDMachine]
    ) -> (save: [RDMachine], delete: [RDMachine.ID]) {
        let desktops = devices.filter { $0.isComputer && !$0.isRegistration(of: UURemoteAccount.clientName) && $0.deviceID != ownDeviceID }
        let present = Set(desktops.map(\.deviceID))
        var save: [RDMachine] = []
        for device in desktops {
            if var machine = machines.first(where: { $0.uuDeviceID == device.deviceID }) {
                let before = machine
                // The name follows the device's until the user gives it one.
                let oldAlias = machine.uuDeviceAlias.isEmpty ? device.deviceID : machine.uuDeviceAlias
                if machine.name == oldAlias, !device.alias.isEmpty { machine.name = device.alias }
                machine.uuDeviceAlias = device.alias
                if machine != before { save.append(machine) }
            } else {
                save.append(makeMachine(for: device, folder: folder))
            }
        }
        let delete = machines
            .filter { $0.folderId == folder && $0.uuManaged && !present.contains($0.uuDeviceID) }
            .map(\.id)
        return (save, delete)
    }
}
