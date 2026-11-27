//
//  MenubarTool.swift
//  Rayon
//

#if os(macOS)
import Foundation
import MachineStatusView
import RayonModule

@MainActor
class MenubarTool {
    static let shared = MenubarTool()

    var statusItem: [MenubarStatusItem] = []
    var hasCat: Bool { !statusItem.isEmpty }

    private init() {}

    private static let persistedKey = "me.mizorewww.rayon.menubarMachines"

    private func persist() {
        let ids = statusItem.map(\.machine.id.uuidString)
        UserDefaults.standard.set(ids, forKey: Self.persistedKey)
        AppDelegate.shared?.updateActivationPolicy()
    }

    func restore() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.persistedKey) ?? []
        for id in ids.compactMap(UUID.init(uuidString:)) {
            createRuncat(for: id, quiet: true)
        }
        persist()
    }

    func createRuncat(for machineId: RDMachine.ID, quiet: Bool = false) {
        func fail(_ message: String) {
            if !quiet { UIBridge.presentError(with: message, delay: 0) }
        }
        for item in statusItem where item.machine.id == machineId {
            fail("This server is already in the menu bar")
            return
        }

        guard let machine = RayonStore.shared.machine(machineId) else {
            fail("Could not add the server to the menu bar: its details are missing")
            return
        }
        guard machine.associatedIdentity != nil else {
            fail("To show a server in the menu bar, choose an identity for it first (Edit Server › Identity)")
            return
        }
        guard RayonStore.shared.associatedIdentity(for: machine) != nil else {
            fail("Could not add the server to the menu bar: its identity is missing")
            return
        }
        // The monitor page's session when it is open: one connection per
        // server, however many places show it.
        guard let session = try? MonitorCenter.shared.hold(machine.id) else {
            fail("Could not add the server to the menu bar: its details are missing")
            return
        }
        statusItem.append(MenubarStatusItem(machine: machine, session: session))
        if !quiet { persist() }
    }

    #if DEBUG
        func showPreview() {
            let machine = RDMachine(remoteAddress: "203.0.113.10", remotePort: "22", name: "web-01")
            let item = MenubarStatusItem(machine: machine, session: .preview(machine: machine))
            statusItem.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item.togglePopover() }
        }
    #endif

    func item(withKey key: String) -> MenubarStatusItem? {
        statusItem.first { $0.key == key }
    }

    func remove(menubarItem: MenubarStatusItem.ID) {
        statusItem.removeAll { $0.id == menubarItem }
        persist()
    }
}

#endif
