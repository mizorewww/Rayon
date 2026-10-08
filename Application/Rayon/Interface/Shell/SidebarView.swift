//
//  SidebarView.swift
//  Rayon (macOS)
//
//  Home · Manage · Sessions · File Transfer · Settings.
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

    var body: some View {
        List(selection: selection) {
            Label("Home", systemImage: "house")
                .tag(Route.home)

            Section("Manage") {
                Label("Servers", systemImage: "server.rack")
                    .badge(store.machineGroup.count)
                    .tag(Route.servers)
                Label("Identities", systemImage: "person")
                    .badge(store.identityGroup.count)
                    .tag(Route.identities)
                Label("Snippets", systemImage: "chevron.left.forwardslash.chevron.right")
                    .badge(store.snippetGroup.count)
                    .tag(Route.snippets)
                Label("Port Forward", systemImage: "arrow.right")
                    .badge(store.portForwardGroup.count)
                    .tag(Route.portForward)
            }

            if !terminals.sessionContexts.isEmpty || !monitors.sessions.isEmpty {
                Section {
                    ForEach(terminals.sessionContexts) { context in
                        TerminalSidebarRow(context: context)
                            .tag(Route.terminal(context.id))
                    }
                    ForEach(monitors.sessions) { session in
                        MonitorSidebarRow(session: session)
                            .tag(Route.monitor(session.id))
                    }
                } header: {
                    HStack {
                        Text("Sessions")
                        Spacer()
                        Button {
                            router.batchStartup()
                        } label: {
                            Image(systemName: "wind")
                        }
                        .buttonStyle(.borderless)
                        .help("Batch Startup")
                    }
                }
            }

            if !transfers.transfers.isEmpty {
                Section("File Transfer") {
                    ForEach(transfers.transfers) { context in
                        TransferSidebarRow(context: context)
                            .tag(Route.transfer(context.id))
                    }
                }
            }

            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(Route.settings)
            }
        }
        .listStyle(.sidebar)
    }
}

/// A session row: SF Symbol, title, and a live dot.
private struct SessionLabel: View {
    let title: String
    let systemImage: String
    let status: RXStatus

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            StatusDot(status, size: .small)
        }
    }
}

private struct TerminalSidebarRow: View {
    @ObservedObject var context: TerminalManager.Context

    var body: some View {
        SessionLabel(
            title: context.remoteType == .machine ? context.machine.name : context.navigationTitle,
            systemImage: "terminal",
            status: context.interfaceDisabled ? .off : .success
        )
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
        SessionLabel(title: session.machine.name, systemImage: "waveform.path.ecg", status: session.health.status)
            .contextMenu {
                Button("Open Terminal") { AppRouter.shared.openTerminal(machine: session.machine.id) }
                Button("Close Monitor") { MonitorCenter.shared.end(session.id) }
            }
    }
}

private struct TransferSidebarRow: View {
    @ObservedObject var context: FileTransferContext

    var body: some View {
        SessionLabel(
            title: context.machine.name,
            systemImage: "arrow.up.arrow.down",
            status: context.connected ? .success : (context.processConnection ? .running : .off)
        )
        .contextMenu {
            if !context.connected {
                Button("Reconnect") { context.processBootstrap() }
            }
            Button("Close File Transfer") { FileTransferSessionActions.close(context) }
        }
    }
}
