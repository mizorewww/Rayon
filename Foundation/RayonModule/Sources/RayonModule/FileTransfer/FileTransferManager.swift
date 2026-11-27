//
//  FileTransferManager.swift
//  RayonModule
//
//  Shared transfer session registry, previously duplicated between the
//  macOS and iOS apps. Confirmation/error presentation goes through
//  FileTransferInterface.
//

import Foundation
import SwiftUI

/// The registry and its transfers are main-thread state, like the
/// interface showing them.
@MainActor
public class FileTransferManager: ObservableObject {
    public static let shared = FileTransferManager()

    private init() {}

    @Published public var transfers: [FileTransferContext] = []

    public func begin(for machineId: RDMachine.ID, force: Bool = false) {
        if !force {
            for transfer in transfers where transfer.machine.id == machineId {
                FileTransferInterface.uiHandler.requiresConfirmation(
                    String(localized: "Another file transfer for this machine is already running", bundle: .module)
                ) { confirmed in
                    guard confirmed else {
                        return
                    }
                    self.begin(for: machineId, force: true)
                }
                return
            }
        }
        guard let machine = RayonStore.shared.machine(machineId) else {
            FileTransferInterface.uiHandler.presentError(String(localized: "Unknown Bad Data", bundle: .module))
            return
        }
        let object = FileTransferContext(machine: machine, identity: RayonStore.shared.associatedIdentity(for: machine))
        transfers.append(object)
        Telemetry.record(.feature(.sftpBrowsed))
    }

    public func end(for contextId: UUID) {
        onMainThread { [self] in
            let index = transfers.firstIndex { $0.id == contextId }
            guard let index = index else { return }
            let sftp = transfers.remove(at: index)
            sftp.processShutdown()
            sftp.destroyedSession = true
        }
    }
}
