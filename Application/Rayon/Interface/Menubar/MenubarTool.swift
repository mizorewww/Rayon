//
//  MenubarTool.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/1.
//

import AppKit
import RayonModule

class MenubarTool {
    let bootstrapLock = NSLock()

    // Keep the existing caller-managed queue and lock ownership.
    nonisolated(unsafe) static let shared = MenubarTool()

    var statusItem: [MenubarStatusItem] = []
    var hasCat: Bool {
        bootstrapLock.lock()
        let ret = !statusItem.isEmpty
        bootstrapLock.unlock()
        return ret
    }

    private init() {}

    struct ArgumentCompiler: Codable {
        let machine: RDMachine.ID
        let identity: RDIdentity.ID

        init(machine: RDMachine.ID, identity: RDIdentity.ID) {
            self.machine = machine
            self.identity = identity
        }

        @MainActor func createStatusItem() -> MenubarStatusItem? {
            let machine = RayonStore.shared.machineGroup[machine]
            let identity = RayonStore.shared.identityGroup[identity]
            // Callers validate these invariants and present errors already;
            // degrade gracefully instead of crashing the whole app.
            guard machine.isNotPlaceholder(), !identity.username.isEmpty else {
                debugPrint("failed to create status item: malformed machine or identity")
                return nil
            }
            return .init(machine: machine, identity: identity)
        }
    }

    @MainActor func createRuncat(for machineId: RDMachine.ID) {
        bootstrapLock.lock()
        let copy = statusItem
        bootstrapLock.unlock()
        for item in copy where item.machine.id == machineId {
            UIBridge.presentError(
                with: "Another cat is running for this machine",
                delay: 0
            )
            return
        }

        let machine = RayonStore.shared.machineGroup[machineId]
        guard machine.isNotPlaceholder() else {
            UIBridge.presentError(
                with: "Could not create menubar app: malformed machine info",
                delay: 0
            )
            return
        }
        guard let identityIdStr = machine.associatedIdentity,
              let identityId = UUID(uuidString: identityIdStr)
        else {
            UIBridge.presentError(
                with: "Could not create menubar app: login identity of this machine must be set",
                delay: 0
            )
            return
        }
        let identity = RayonStore.shared.identityGroup[identityId]
        guard !identity.username.isEmpty else {
            UIBridge.presentError(
                with: "Could not create menubar app: malformed identity info",
                delay: 0
            )
            return
        }
        let compiler = ArgumentCompiler(machine: machine.id, identity: identity.id)
        guard let item = compiler.createStatusItem() else {
            return
        }
        bootstrapLock.lock()
        statusItem.append(item)
        bootstrapLock.unlock()
    }

    func remove(menubarItem: MenubarStatusItem.ID) {
        bootstrapLock.lock()
        statusItem = statusItem
            .filter { $0.id != menubarItem }
        bootstrapLock.unlock()
    }
}
