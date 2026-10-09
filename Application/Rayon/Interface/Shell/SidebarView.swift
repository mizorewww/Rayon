//
//  SidebarView.swift
//  Rayon (macOS)
//
//  Home · Manage · Sessions (terminals, files, monitors), with Settings pinned
//  to the bottom-left corner.
//

import MachineStatusView
import RayonModule
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var router = AppRouter.shared
    @ObservedObject var terminals = TerminalManager.shared
    @ObservedObject var monitors = MonitorCenter.shared
    @ObservedObject var transfers = FileTransferManager.shared

    var selection: Binding<Route?> {
        Binding(get: { router.route }, set: { if let route = $0 { router.route = route } })
    }

    /// Changes whenever a session opens or closes; drives the row animation.
    private var sessionIDs: [UUID] {
        terminals.sessionContexts.map(\.id) + transfers.transfers.map(\.id) + monitors.sessions.map(\.id)
    }

    var body: some View {
        List(selection: selection) {
            Label("Home", systemImage: "house")
                .tag(Route.home)

            Section("Manage") {
                Label("Servers", systemImage: "server.rack")
                    .badge(store.machineGroup.count)
                    .tag(Route.servers)
                Label("Identities", systemImage: "person.badge.key")
                    .badge(store.identityGroup.count)
                    .tag(Route.identities)
                Label("Snippets", systemImage: "chevron.left.forwardslash.chevron.right")
                    .badge(store.snippetGroup.count)
                    .tag(Route.snippets)
                Label("Port Forward", systemImage: "arrow.left.arrow.right")
                    .badge(store.portForwardGroup.count)
                    .tag(Route.portForward)
            }

            if !sessionIDs.isEmpty {
                Section("Sessions") {
                    ForEach(terminals.sessionContexts) { context in
                        TerminalSidebarRow(context: context)
                            .tag(Route.terminal(context.id))
                    }
                    ForEach(transfers.transfers) { context in
                        TransferSidebarRow(context: context)
                            .tag(Route.transfer(context.id))
                    }
                    ForEach(monitors.sessions) { session in
                        MonitorSidebarRow(session: session)
                            .tag(Route.monitor(session.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.25), value: sessionIDs)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // A one-row list of its own keeps Settings pinned to the bottom-left
            // corner while drawing it exactly like the rows above.
            List(selection: selection) {
                Label("Settings", systemImage: "gearshape")
                    .tag(Route.settings)
                    .help("Settings (⌘,)")
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 48)
        }
    }
}

/// A session row: SF Symbol and title.
private struct SessionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

private struct TerminalSidebarRow: View {
    @ObservedObject var context: TerminalManager.Context

    var body: some View {
        SessionLabel(
            title: context.displayName,
            systemImage: ServerTool.terminal.systemImage
        )
        .help("Terminal")
        .contextMenu {
            if context.closed {
                Button("Reconnect") { context.reconnect() }
            }
            Button("Close Session") { TerminalSessionActions.close(context) }
        }
    }
}

private struct MonitorSidebarRow: View {
    @ObservedObject var session: MonitorSession

    var body: some View {
        SessionLabel(title: session.machine.name, systemImage: ServerTool.monitor.systemImage)
            .help("Monitor")
            .contextMenu {
                Button("New Terminal") { AppRouter.shared.openTerminal(machine: session.machine.id) }
                Button("Close Monitor") { MonitorCenter.shared.end(session.id) }
            }
    }
}

private struct TransferSidebarRow: View {
    @ObservedObject var context: FileTransferContext

    var body: some View {
        SessionLabel(
            title: context.machine.name,
            systemImage: ServerTool.files.systemImage
        )
        .help("Files")
        .contextMenu {
            if !context.connected {
                Button("Reconnect") { context.processBootstrap() }
            }
            Button("Close Files") { FileTransferSessionActions.close(context) }
        }
    }
}
