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
            informative: "Port forwards through it stop working.",
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

/// The three ways into a server. Every surface that opens one (tiles, table rows,
/// context menus, the session switcher, the sidebar) uses these names, symbols and
/// descriptions, so a button means the same thing wherever it appears.
enum ServerTool: CaseIterable, Identifiable {
    case terminal
    case files
    case monitor

    var id: Self { self }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .files: return "Files"
        case .monitor: return "Monitor"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .files: return "folder"
        case .monitor: return "gauge.with.dots.needle.33percent"
        }
    }

    /// Tooltip: what the tool does, in a sentence.
    var help: String {
        switch self {
        case .terminal: return "Open an SSH terminal on this server"
        case .files: return "Browse, upload and download files over SFTP"
        case .monitor: return "Watch CPU, memory, disk and network usage"
        }
    }

    /// Shows this tool for the server, reusing a session that is already open.
    @MainActor
    func show(_ machine: RDMachine.ID) {
        let router = AppRouter.shared
        switch self {
        case .terminal:
            if let existing = TerminalManager.shared.sessionContexts.first(where: { $0.remoteType == .machine && $0.machine.id == machine }) {
                router.route = .terminal(existing.id)
            } else {
                router.openTerminal(machine: machine)
            }
        case .files: router.openFileTransfer(machine: machine)
        case .monitor: router.openMonitor(machine: machine)
        }
    }
}

/// Terminal, Files, Monitor, Show in Menu Bar, Edit, Duplicate, Copy Address,
/// Copy SSH Command, Delete.
struct ServerContextMenu: View {
    let machine: RDMachine.ID

    var body: some View {
        let router = AppRouter.shared
        Group {
            Button {
                router.openTerminal(machine: machine)
            } label: {
                Label("New Terminal", systemImage: ServerTool.terminal.systemImage)
            }
            Button {
                ServerTool.files.show(machine)
            } label: {
                Label("Open Files", systemImage: ServerTool.files.systemImage)
            }
            Button {
                ServerTool.monitor.show(machine)
            } label: {
                Label("Open Monitor", systemImage: ServerTool.monitor.systemImage)
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

/// Live figures of a server while its monitor is open.
struct ServerLiveState {
    let cpu: Double?
    let memory: Double?

    @MainActor
    static func of(_ machine: RDMachine.ID) -> ServerLiveState {
        if let session = MonitorCenter.shared.session(for: machine),
           session.phase == .connected, session.status.hasData
        {
            return ServerLiveState(
                cpu: Double(session.status.processor.summary.sumUsed),
                memory: session.status.memoryUsedPercent
            )
        }
        return ServerLiveState(cpu: nil, memory: nil)
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

/// Terminal · Files · Monitor for one server, centred in a session page's toolbar,
/// so moving between the three views of a server is one click from any of them.
struct ServerToolSwitcher: View {
    let machine: RDMachine.ID
    let current: ServerTool

    var body: some View {
        Picker("View", selection: Binding(get: { current }, set: { $0.show(machine) })) {
            ForEach(ServerTool.allCases) { tool in
                Label(tool.title, systemImage: tool.systemImage)
                    .labelStyle(.titleAndIcon)
                    .help(tool.help)
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Switch between this server's terminal, files and monitor")
    }
}

extension View {
    /// Places the `ServerToolSwitcher` in the centre of the window toolbar.
    func serverToolSwitcher(machine: RDMachine.ID?, current: ServerTool) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                if let machine {
                    ServerToolSwitcher(machine: machine, current: current)
                }
            }
        }
    }
}
