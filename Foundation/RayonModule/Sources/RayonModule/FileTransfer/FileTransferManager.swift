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

public class FileTransferManager: ObservableObject {
    // Preserve the existing UI/transfer queue contract.
    nonisolated(unsafe) public static let shared = FileTransferManager()

    private init() {}

    @Published public var transfers: [FileTransferContext] = []

    public func begin(for machineId: RDMachine.ID, force: Bool = false) {
        assert(Thread.isMainThread, "accessing to property terminals requires main thread")
        debugPrint("\(self) \(#function) \(machineId)")
        if !force {
            for transfer in transfers where transfer.machine.id == machineId {
                FileTransferInterface.uiHandler.requiresConfirmation(
                    "Another file transfer for this machine is already running"
                ) { confirmed in
                    guard confirmed else {
                        return
                    }
                    self.begin(for: machineId, force: true)
                }
                return
            }
        }
        let machine = RayonStore.shared.machineGroup[machineId]
        guard machine.isNotPlaceholder() else {
            FileTransferInterface.uiHandler.presentError("Unknown Bad Data")
            return
        }
        var get: RDIdentity?
        if let sid = machine.associatedIdentity,
           let uid = UUID(uuidString: sid),
           RayonStore.shared.identityGroup[uid].username.count > 0
        {
            get = RayonStore.shared.identityGroup[uid]
        }
        let object = FileTransferContext(machine: machine, identity: get)
        transfers.append(object)
    }

    public func end(for contextId: UUID) {
        onMainThread { [self] in
            debugPrint("\(self) \(#function) \(contextId)")
            let index = transfers.firstIndex { $0.id == contextId }
            guard let index = index else { return }
            let sftp = transfers.remove(at: index)
            sftp.processShutdown()
            sftp.destroyedSession = true
        }
    }
}
