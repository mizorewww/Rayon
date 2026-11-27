//
//  ServerActions+macOS.swift
//  Rayon
//
//  The server context menu (Servers table, Dashboard tiles) and the actions behind it.
//

#if os(macOS)
    import MachineStatusView
    import RayonDesign
    import RayonModule
    import SwiftUI

    @MainActor
    enum ServerActions {
        @MainActor
        static func edit(_ machine: RDMachine.ID) {
            AppRouter.shared.present { dismiss in
                ServerEditorSheet(machine: machine, close: dismiss)
            }
        }

        /// New Server, filled in from `template`.
        @MainActor
        static func create(from template: RDMachine? = nil) {
            AppRouter.shared.present { dismiss in
                ServerEditorSheet(machine: nil, template: template, close: dismiss)
            }
        }

        static func duplicate(_ machine: RDMachine.ID) {
            let store = RayonStore.shared
            guard let original = store.machine(machine) else { return }
            Indicator.confirm(
                message: "Duplicate \(original.name)?",
                confirmTitle: "Duplicate"
            ) { confirmed in
                guard confirmed else { return }
                var copy = original
                copy.id = UUID()
                copy.name = original.name + " copy"
                store.save(copy)
            }
        }

        @MainActor
        static func delete(_ machines: [RDMachine.ID]) {
            let store = RayonStore.shared
            guard !machines.isEmpty else { return }
            let message = machines.count == 1
                ? "Delete \(store.machine(machines[0])?.name ?? "this server")?"
                : "Delete \(machines.count) servers?"
            Indicator.confirm(
                message: message,
                informative: "Port forwards through it stop working.",
                confirmTitle: "Delete"
            ) { confirmed in
                guard confirmed else { return }
                for machine in machines {
                    if let session = MonitorCenter.shared.session(for: machine) {
                        MonitorCenter.shared.end(session.id)
                    }
                    store.deleteMachines([machine])
                }
                store.cleanRecentIfNeeded()
            }
        }

        /// For a server whose keys were replaced: its next host key is saved.
        /// The next terminal checks the server for Ghostty's terminfo again and
        /// installs it if it is missing (say, after ~/.terminfo was cleared).
        @MainActor
        static func reinstallTerminfo(_ machine: RDMachine.ID) {
            RayonStore.shared.updateMachine(machine) { $0.forgetGhosttyTerminfo() }
        }

        static func forgetHostKey(_ machine: RDMachine.ID) {
            guard let read = RayonStore.shared.machine(machine) else { return }
            Indicator.confirm(
                message: "Forget the host key of \(read.name)?",
                informative: "The key the server presents on the next connection is saved as its key. Do this only when you know its keys were replaced.",
                confirmTitle: "Forget"
            ) { confirmed in
                guard confirmed else { return }
                read.forgetHostKey()
            }
        }

        static func copyAddress(_ machine: RDMachine.ID) {
            guard let read = RayonStore.shared.machine(machine) else { return }
            Pasteboard.copy("\(read.remoteAddress):\(read.remotePort)")
        }

        static func copyCommand(_ machine: RDMachine.ID) {
            guard let read = RayonStore.shared.machine(machine) else { return }
            Pasteboard.copy(read.getCommand { RayonStore.shared.machine($0) })
        }
    }

    extension ServerTool {
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
            case .editor: router.openEditor(machine: machine)
            case .monitor: router.openMonitor(machine: machine)
            case .desktop: router.openDesktop(machine: machine)
            }
        }
    }

    /// Terminal, Files, Monitor, Show in Menu Bar, Edit, Duplicate, Copy Address
    /// (a UU device's id), Copy SSH Command, Forget Host Key, Delete.
    struct ServerContextMenu: View {
        let machine: RDMachine.ID
        /// False where the tools already sit beside the menu (a tile's ⋯ button).
        var includesTools = true

        var body: some View {
            sshItems
        }

        @ViewBuilder private var sshItems: some View {
            let router = AppRouter.shared
            let read = (RayonStore.shared.machine(machine) ?? RDMachine())
            Group {
                if includesTools {
                    RXMenuItem("Open Terminal", systemImage: ServerTool.terminal.systemImage) {
                        ServerTool.terminal.show(machine)
                    }
                    RXMenuItem("Open Files", systemImage: ServerTool.files.systemImage) {
                        ServerTool.files.show(machine)
                    }
                    RXMenuItem("Open Editor", systemImage: ServerTool.editor.systemImage) {
                        ServerTool.editor.show(machine)
                    }
                    RXMenuItem("Open Monitor", systemImage: ServerTool.monitor.systemImage) {
                        ServerTool.monitor.show(machine)
                    }
                    if read.hasRemoteDesktop {
                        RXMenuItem("Open Desktop", systemImage: ServerTool.desktop.systemImage) {
                            ServerTool.desktop.show(machine)
                        }
                        RXMenuItem("View Desktop Only", systemImage: "eye") {
                            router.openDesktop(machine: machine, viewOnly: true)
                        }
                    }
                }
                RXMenuItem("New Terminal", systemImage: "plus.rectangle") {
                    router.openTerminal(machine: machine)
                }
                RXMenuItem("Show in Menu Bar", systemImage: "menubar.rectangle") {
                    router.showInMenuBar(machine: machine)
                }
                Divider()
                RXMenuItem("Edit…", systemImage: "pencil") {
                    ServerActions.edit(machine)
                }
                MoveToFolderMenu(machine: machine)
                RXMenuItem("Duplicate", systemImage: "plus.square.on.square") {
                    ServerActions.duplicate(machine)
                }
                if read.isUURemoteDevice {
                    // Its address is the device id; no ssh command reaches it.
                    RXMenuItem("Copy Device ID", systemImage: "doc.on.doc") {
                        Pasteboard.copy(read.uuDeviceID)
                    }
                } else {
                    RXMenuItem("Copy Address", systemImage: "doc.on.doc") {
                        ServerActions.copyAddress(machine)
                    }
                    RXMenuItem("Copy SSH Command", systemImage: "chevron.left.forwardslash.chevron.right") {
                        ServerActions.copyCommand(machine)
                    }
                }
                RXMenuItem("Forget Host Key…", systemImage: "key.slash") {
                    ServerActions.forgetHostKey(machine)
                }
                if read.hasGhosttyTerminfo {
                    RXMenuItem("Check Terminfo Again", systemImage: "arrow.triangle.2.circlepath") {
                        ServerActions.reinstallTerminfo(machine)
                    }
                    .help("On the next terminal, check that the server still has Ghostty's terminfo, and install it if not")
                }
                Divider()
                RXMenuItem("Delete…", systemImage: "trash", role: .destructive) {
                    ServerActions.delete([machine])
                }
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

    /// Terminal · Files · Editor · Monitor (· Desktop when the server has a remote
    /// desktop) for one server, centred in a session page's toolbar, so moving
    /// between its views is one click from any of them.
    struct ServerToolSwitcher: View {
        let machine: RDMachine.ID
        let current: ServerTool

        private var tools: [ServerTool] {
            ServerTool.available(for: (RayonStore.shared.machine(machine) ?? RDMachine()))
        }

        var body: some View {
            Picker("View", selection: Binding(get: { current }, set: { $0.show(machine) })) {
                ForEach(tools) { tool in
                    Text(tool.title)
                        .help(tool.help(for: (RayonStore.shared.machine(machine) ?? RDMachine())))
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Switch between this server's terminal, files, editor and monitor")
        }
    }

    /// The server and tool a session page shows, for the switcher in its toolbar.
    struct ServerToolSwitch: Equatable {
        let machine: RDMachine.ID
        let current: ServerTool
    }

    private struct ServerToolSwitchKey: EnvironmentKey {
        static let defaultValue: ServerToolSwitch? = nil
    }

    extension EnvironmentValues {
        var serverToolSwitch: ServerToolSwitch? {
            get { self[ServerToolSwitchKey.self] }
            set { self[ServerToolSwitchKey.self] = newValue }
        }
    }

    extension View {
        /// Places the `ServerToolSwitcher` in the centre of the window toolbar. The
        /// page's toolbar (`pageToolbar`) lays it out with the rest, so this goes
        /// outside it.
        func serverToolSwitcher(machine: RDMachine.ID?, current: ServerTool) -> some View {
            environment(\.serverToolSwitch, machine.map { ServerToolSwitch(machine: $0, current: current) })
        }
    }

#endif
