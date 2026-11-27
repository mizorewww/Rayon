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

import Foundation
import UURemoteKit

public enum UURemoteFolderSync {
    /// The id of the server for a UU device, the same on every device.
    public static func machineID(for deviceID: String) -> UUID {
        UUID(derivedFrom: "me.mizorewww.rayon.uu-device.\(deviceID)")
    }

    /// The account's folder the first time, under an id worked out from the
    /// account, so every device signed in to it makes the same folder and
    /// sync keeps one. A "UU Remote" folder not linked to an account gives
    /// it its servers, so they are not left beside an empty one.
    @MainActor static func makeFolder(userID: String, store: RayonStore) -> RDFolder {
        let name = "UU Remote"
        let adopted = store.folder(named: name).flatMap { $0.isLinked ? nil : $0 }
        let folder = RDFolder(
            id: RDFolder.id(uuUserID: userID),
            name: adopted == nil ? store.availableFolderName(name) : name,
            source: .uuRemote(userID: userID)
        )
        store.save(folder)
        if let adopted {
            store.moveServers(store.machines(inFolder: adopted.id).map(\.id), toFolder: folder.id)
            store.deleteFolder(adopted.id)
        }
        return store.folder(folder.id) ?? folder
    }

    /// A server for a device, in `folder`.
    public static func makeMachine(for device: UUDeviceInfo, folder: RDFolder.ID?) -> RDMachine {
        var machine = RDMachine(
            remoteAddress: device.deviceID,
            remotePort: "22",
            name: device.alias.isEmpty ? device.deviceID : device.alias,
            folderId: folder,
            comment: String(localized: "\(UUDeviceInfo.platformName(device.platform)) device", bundle: .module)
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
    /// and `hidden` its other sign-ins and the devices the person removed:
    /// none of them is a server.
    public static func changes(
        devices: [UUDeviceInfo],
        folder: RDFolder.ID,
        ownDeviceID: String = "",
        hidden: Set<String> = [],
        machines: [RDMachine]
    ) -> (save: [RDMachine], delete: [RDMachine.ID]) {
        let desktops = devices.filter {
            $0.isComputer && !$0.isRegistration(of: UURemoteAccount.clientName) && $0.deviceID != ownDeviceID && !hidden.contains($0.deviceID)
        }
        let present = Set(desktops.map(\.deviceID))
        var save: [RDMachine] = []
        for device in desktops {
            if var machine = machines.first(where: { $0.uuDeviceID == device.deviceID }) {
                let before = machine
                follow(device, in: &machine)
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

    /// The server takes the device's alias; its name follows the device's
    /// until the user gives it one.
    public static func follow(_ device: UUDeviceInfo, in machine: inout RDMachine) {
        let oldAlias = machine.uuDeviceAlias.isEmpty ? device.deviceID : machine.uuDeviceAlias
        if machine.name == oldAlias, !device.alias.isEmpty { machine.name = device.alias }
        machine.uuDeviceAlias = device.alias
    }

    /// The UU devices that leave Rayon with `deleted`: a device whose last
    /// server goes. Its folder would otherwise make it a server again.
    public static func devicesLeaving(_ deleted: Set<RDMachine.ID>, of machines: [RDMachine]) -> Set<String> {
        let leaving = Set(machines.filter { deleted.contains($0.id) && $0.isUURemoteDevice }.map(\.uuDeviceID))
        let staying = Set(machines.filter { !deleted.contains($0.id) }.map(\.uuDeviceID))
        return leaving.subtracting(staying)
    }
}
