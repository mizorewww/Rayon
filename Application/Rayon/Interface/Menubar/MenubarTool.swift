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

    /// Servers shown in the menu bar, so they come back after Rayon restarts.
    private static let persistedKey = "wiki.qaq.rayon.menubarMachines"

    private func persist() {
        bootstrapLock.lock()
        let ids = statusItem.map(\.machine.id.uuidString)
        bootstrapLock.unlock()
        UserDefaults.standard.set(ids, forKey: Self.persistedKey)
    }

    /// Puts back the menu bar items from the last run. A server that was deleted,
    /// or lost its identity, is dropped without an alert.
    @MainActor func restore() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.persistedKey) ?? []
        for id in ids.compactMap(UUID.init(uuidString:)) {
            createRuncat(for: id, quiet: true)
        }
        persist()
    }

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

    /// - Parameter quiet: restoring at launch; problems are skipped, not shown.
    @MainActor func createRuncat(for machineId: RDMachine.ID, quiet: Bool = false) {
        func fail(_ message: String) {
            if !quiet { UIBridge.presentError(with: message, delay: 0) }
        }
        bootstrapLock.lock()
        let copy = statusItem
        bootstrapLock.unlock()
        for item in copy where item.machine.id == machineId {
            fail("This server is already in the menu bar")
            return
        }

        let machine = RayonStore.shared.machineGroup[machineId]
        guard machine.isNotPlaceholder() else {
            fail("Could not add the server to the menu bar: its details are missing")
            return
        }
        guard machine.associatedIdentity != nil else {
            fail("To show a server in the menu bar, choose an identity for it first (Edit Server › Identity)")
            return
        }
        guard let identity = RayonStore.shared.associatedIdentity(for: machine) else {
            fail("Could not add the server to the menu bar: its identity is missing")
            return
        }
        let compiler = ArgumentCompiler(machine: machine.id, identity: identity.id)
        guard let item = compiler.createStatusItem() else {
            return
        }
        bootstrapLock.lock()
        statusItem.append(item)
        bootstrapLock.unlock()
        if !quiet { persist() }
    }

    func remove(menubarItem: MenubarStatusItem.ID) {
        bootstrapLock.lock()
        statusItem = statusItem
            .filter { $0.id != menubarItem }
        bootstrapLock.unlock()
        persist()
    }
}
