//
//  ServerActions+macOS.swift
//  Rayon
//
//  Opening a server's editor and its tools on the Mac, the figures its open
//  monitor shows, and the tool switcher of its session pages.
//

#if os(macOS)
    import MachineStatusView
    import RayonDesign
    import RayonModule
    import SwiftUI

    extension ServerActions {
        static func edit(_ machine: RDMachine.ID) {
            AppRouter.shared.present { _ in ServerEditor(machine: machine) }
        }

        /// New Server, filled in from `template`.
        static func create(from template: RDMachine? = nil) {
            AppRouter.shared.present { _ in ServerEditor(template: template) }
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
