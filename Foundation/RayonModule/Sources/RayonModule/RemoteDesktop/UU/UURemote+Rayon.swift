//
//  UURemote+Rayon.swift
//  RayonModule
//
//  Rayon's UU Remote account and connections, from UURemoteKit: the
//  sign-in kept in the keychain, the account's devices as servers in a
//  folder, and a server's UU device as a connection target.
//

import Foundation
@_exported import UURemoteKit

public extension UURemoteAccount {
    /// The name Rayon registers its own UU device under.
    nonisolated static let clientName = "Rayon"

    /// Rayon's account. Its devices fill the account's folder after every
    /// refresh.
    @MainActor static let shared: UURemoteAccount = {
        // The sign-in used to be an AES blob in the defaults; it is in the
        // keychain now, and the old one only goes.
        UserDefaults.standard.removeObject(forKey: "me.mizorewww.rayon.uuremote.account")
        UserDefaults.standard.removeObject(forKey: "me.mizorewww.rayon.uuremote.nickname")
        let account = UURemoteAccount(
            storage: UUKeychainCredentialStorage(service: "me.mizorewww.rayon.uu-remote"),
            clientName: clientName
        )
        account.onDevicesRefreshed = { [weak account] _ in account?.syncFolder() }
        return account
    }()

    /// "1 desktop device", "3 desktop devices".
    nonisolated static func deviceCount(_ count: Int) -> String {
        count == 1 ? "1 desktop device" : "\(count) desktop devices"
    }

    /// The folder this account's devices are in, if it was made.
    @MainActor func folder(store: RayonStore = .shared) -> RDFolder? {
        guard !userID.isEmpty else { return nil }
        return store.folders.first { $0.source == .uuRemote(userID: userID) }
    }

    /// Puts the devices in the account's folder, making the folder the
    /// first time.
    @MainActor func syncFolder(store: RayonStore = .shared) {
        guard isLoggedIn, !userID.isEmpty else { return }
        let folder = folder(store: store) ?? adoptOrCreateFolder(store: store)
        let changes = UURemoteFolderSync.changes(
            devices: devices,
            folder: folder.id,
            ownDeviceID: credentials.deviceID,
            machines: store.machines
        )
        for machine in changes.save {
            // One saved already follows its device as it is saved now.
            if store.machine(machine.id) != nil, let device = devices.first(where: { $0.deviceID == machine.uuDeviceID }) {
                store.updateMachine(machine.id) { UURemoteFolderSync.follow(device, in: &$0) }
            } else {
                store.save(machine)
            }
        }
        store.deleteMachines(changes.delete)
    }

    @MainActor private func adoptOrCreateFolder(store: RayonStore) -> RDFolder {
        UURemoteFolderSync.makeFolder(userID: userID, store: store)
    }

    /// A server for a device, in the account's folder.
    @MainActor func makeMachine(for device: UUDeviceInfo, store: RayonStore = .shared) -> RDMachine {
        UURemoteFolderSync.makeMachine(for: device, folder: folder(store: store)?.id)
    }

    /// The saved server bound to a device, if one is.
    @MainActor func savedMachine(for device: UUDeviceInfo, store: RayonStore = .shared) -> RDMachine? {
        store.machines.first { $0.uuDeviceID == device.deviceID }
    }

    /// The saved server bound to a device, adding one when there is none.
    @MainActor func upsertMachine(for device: UUDeviceInfo, store: RayonStore = .shared) -> RDMachine {
        if let existing = savedMachine(for: device, store: store) { return existing }
        let machine = makeMachine(for: device, store: store)
        store.save(machine)
        return machine
    }

    #if DEBUG
        /// Debug builds: takes a sign-in from a JSON `UUCredentials` file,
        /// for screenshots against real devices. It is not kept.
        @MainActor func adoptSessionForPreview(from url: URL) async {
            guard let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(UUCredentials.self, from: data)
            else { return }
            await adopt(saved)
        }
    #endif
}

public extension UURemoteConnections {
    /// The connections of Rayon's account.
    @MainActor static let shared = UURemoteConnections(account: .shared)
}

public extension RDMachine {
    /// The UU device (or remote-assistance share) this server connects to.
    var uuTarget: UURemoteTarget {
        UURemoteTarget(
            deviceID: uuDeviceID.isEmpty ? remoteAddress : uuDeviceID,
            assistID: uuAssistID,
            assistCode: uuAssistCode
        )
    }
}

@MainActor
public extension UURemoteConnections {
    /// A server's UU device's terminal sessions, most recently used first.
    func sessions(for machine: RDMachine) async throws -> [UUTerminalSession] {
        try await terminalSessions(on: machine.uuTarget)
    }

    /// Ends a session no terminal here is attached to.
    func endSession(_ id: UInt32, on machine: RDMachine) async throws {
        try await endTerminalSession(id, on: machine.uuTarget)
    }

    /// What the server's UU connection is doing, for a terminal waiting on it.
    func status(for machine: RDMachine) -> String {
        status(of: machine.uuTarget)
    }
}
