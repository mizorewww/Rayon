//
//  ServerActions.swift
//  Rayon (macOS)
//
//  The server context menu (Servers table, Home tiles) and the actions behind it.
//

import MachineStatusView
import RayonModule
import SwiftUI

enum ServerActions {
    @MainActor
    static func edit(_ machine: RDMachine.ID) {
        SheetPresenter.present { dismiss in
            ServerEditorSheet(machine: machine, close: dismiss)
        }
    }

    static func duplicate(_ machine: RDMachine.ID) {
        let store = RayonStore.shared
        let original = store.machineGroup[machine]
        guard original.isNotPlaceholder() else { return }
        UIBridge.requiresConfirmation(
            message: "Duplicate \(original.name)?",
            informative: "The copy keeps the address, identity and group.",
            confirmTitle: "Duplicate"
        ) { confirmed in
            guard confirmed else { return }
            var copy = original
            copy.id = UUID()
            copy.name = original.name + " copy"
            store.machineGroup.insert(copy)
        }
    }

    static func delete(_ machines: [RDMachine.ID]) {
        let store = RayonStore.shared
        guard !machines.isEmpty else { return }
        let message = machines.count == 1
            ? "Delete \(store.machineGroup[machines[0]].name)?"
            : "Delete \(machines.count) servers?"
        UIBridge.requiresConfirmation(
            message: message,
            informative: "Open sessions stay open. Port forwards through it stop working.",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            for machine in machines {
                if let session = MonitorCenter.shared.session(for: machine) {
                    MonitorCenter.shared.end(session.id)
                }
                store.machineGroup.delete(machine)
            }
            store.cleanRecentIfNeeded()
        }
    }

    static func copyAddress(_ machine: RDMachine.ID) {
        let read = RayonStore.shared.machineGroup[machine]
        UIBridge.sendPasteboard(str: "\(read.remoteAddress):\(read.remotePort)")
    }

    static func copyCommand(_ machine: RDMachine.ID) {
        UIBridge.sendPasteboard(str: RayonStore.shared.machineGroup[machine].getCommand())
    }
}

/// Open Terminal ↩, Open Monitor, Open File Transfer, Show in Menu Bar, Edit,
/// Duplicate, Copy Address, Delete. The same items appear in a row's ⋯ button.
struct ServerContextMenu: View {
    let machine: RDMachine.ID

    var body: some View {
        let router = AppRouter.shared
        Group {
            Button {
                router.openTerminal(machine: machine)
            } label: {
                Label("Open Terminal", systemImage: "terminal")
            }
            Button {
                router.openMonitor(machine: machine)
            } label: {
                Label("Open Monitor", systemImage: "waveform.path.ecg")
            }
            Button {
                router.openFileTransfer(machine: machine)
            } label: {
                Label("Open File Transfer", systemImage: "arrow.up.arrow.down")
            }
            Button {
                router.showInMenuBar(machine: machine)
            } label: {
                Label("Show in Menu Bar", systemImage: "menubar.rectangle")
            }
            Divider()
            Button {
                ServerActions.edit(machine)
            } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Button {
                ServerActions.duplicate(machine)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                ServerActions.copyAddress(machine)
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            Button {
                ServerActions.copyCommand(machine)
            } label: {
                Label("Copy SSH Command", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Divider()
            Button(role: .destructive) {
                ServerActions.delete([machine])
            } label: {
                Label("Delete…", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}

/// Live state of a server as far as the app knows it: an open monitor or terminal.
struct ServerLiveState {
    let status: RXStatus
    let text: String
    let cpu: Double?
    let memory: Double?

    @MainActor
    static func of(_ machine: RDMachine.ID) -> ServerLiveState {
        if let session = MonitorCenter.shared.session(for: machine) {
            let health = session.health
            let hasData = session.phase == .connected && session.status.hasData
            return ServerLiveState(
                status: health.status,
                text: health.text,
                cpu: hasData ? Double(session.status.processor.summary.sumUsed) : nil,
                memory: hasData ? session.status.memoryUsedPercent : nil
            )
        }
        if TerminalManager.shared.sessionAlive(forMachine: machine) {
            return ServerLiveState(status: .success, text: "Connected", cpu: nil, memory: nil)
        }
        return ServerLiveState(status: .off, text: "Not monitored", cpu: nil, memory: nil)
    }
}

/// Re-renders its content as the server's monitor or terminal changes.
struct ServerLiveReader<Content: View>: View {
    let machine: RDMachine.ID
    @ViewBuilder let content: (ServerLiveState) -> Content

    @ObservedObject private var monitors = MonitorCenter.shared
    @ObservedObject private var terminals = TerminalManager.shared

    var body: some View {
        if let session = monitors.session(for: machine) {
            SessionReader(session: session) { content(ServerLiveState.of(machine)) }
        } else {
            content(ServerLiveState.of(machine))
        }
    }

    private struct SessionReader<Inner: View>: View {
        @ObservedObject var session: MonitorSession
        @ViewBuilder let inner: () -> Inner
        var body: some View { inner() }
    }
}
