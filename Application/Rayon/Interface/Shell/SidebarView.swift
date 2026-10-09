//
//  SidebarView.swift
//  Rayon (macOS)
//
//  Home · Manage · Sessions (one row per server with open sessions; the page's
//  toolbar switches between its Terminal, Files and Monitor), with Settings
//  pinned to the bottom-left corner.
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

    /// A place (Home, Servers…) or a server with open sessions. Selecting a
    /// server shows the tool it showed last; the toolbar switcher changes tools.
    enum Item: Hashable {
        case place(Route)
        case owner(SessionOwner)
    }

    var selection: Binding<Item?> {
        Binding(get: {
            if router.route.isSession {
                return router.owner(of: router.route).map(Item.owner)
            }
            return .place(router.route)
        }, set: { item in
            switch item {
            case let .place(route): router.route = route
            case let .owner(owner): router.show(owner)
            case nil: break
            }
        })
    }

    /// Changes whenever a session opens or closes; drives the row animation.
    private var sessionIDs: [UUID] {
        terminals.sessionContexts.map(\.id) + transfers.transfers.map(\.id) + monitors.sessions.map(\.id)
    }

    var body: some View {
        List(selection: selection) {
            Label("Home", systemImage: "house")
                .tag(Item.place(.home))

            Section("Manage") {
                Label("Servers", systemImage: "server.rack")
                    .badge(store.machineGroup.count)
                    .tag(Item.place(.servers))
                Label("Identities", systemImage: "person.badge.key")
                    .badge(store.identityGroup.count)
                    .tag(Item.place(.identities))
                Label("Snippets", systemImage: "chevron.left.forwardslash.chevron.right")
                    .badge(store.snippetGroup.count)
                    .tag(Item.place(.snippets))
                Label("Port Forward", systemImage: "arrow.left.arrow.right")
                    .badge(store.portForwardGroup.count)
                    .tag(Item.place(.portForward))
            }

            if !sessionIDs.isEmpty {
                Section("Sessions") {
                    ForEach(router.openOwners, id: \.self) { owner in
                        OwnerSidebarRow(owner: owner)
                            .tag(Item.owner(owner))
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
                    .tag(Item.place(.settings))
                    .help("Settings (⌘,)")
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 48)
        }
    }
}

/// A server with open sessions (or a Quick Connect terminal): its name, then
/// small symbols for the tools that are open.
private struct OwnerSidebarRow: View {
    let owner: SessionOwner
    @EnvironmentObject var store: RayonStore
    @ObservedObject var terminals = TerminalManager.shared
    @ObservedObject var transfers = FileTransferManager.shared
    @ObservedObject var monitors = MonitorCenter.shared

    private var routes: [Route] { AppRouter.shared.routes(of: owner) }

    private var title: String {
        switch owner {
        case let .server(id):
            return store.machineGroup[id].name
        case let .command(id):
            return terminals.sessionContexts.first { $0.id == id }?.displayName ?? "Terminal"
        }
    }

    private var openTools: [ServerTool] {
        ServerTool.allCases.filter { tool in
            routes.contains { route in
                switch (tool, route) {
                case (.terminal, .terminal), (.files, .transfer), (.monitor, .monitor): return true
                default: return false
                }
            }
        }
    }

    var body: some View {
        HStack(spacing: RX.Space.s2) {
            Label {
                RedactableText(title, redacted: store.machineRedacted == .all)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: { if case .command = owner { return "terminal" } else { return "server.rack" } }())
            }
            Spacer(minLength: 0)
            if case .server = owner {
                HStack(spacing: 3) {
                    ForEach(openTools) { tool in
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .help(openTools.map(\.title).joined(separator: ", ") + " open")
        .contextMenu { menu }
    }

    @ViewBuilder var menu: some View {
        ForEach(routes, id: \.self) { route in
            switch route {
            case let .terminal(id):
                if let context = terminals.sessionContexts.first(where: { $0.id == id }) {
                    if context.closed { Button("Reconnect Terminal") { context.reconnect() } }
                    Button("Close Terminal") { TerminalSessionActions.close(context) }
                }
            case let .transfer(id):
                if let context = transfers.transfers.first(where: { $0.id == id }) {
                    Button("Close Files") { FileTransferSessionActions.close(context) }
                }
            case let .monitor(id):
                Button("Close Monitor") { MonitorCenter.shared.end(id) }
            default:
                EmptyView()
            }
        }
        if routes.count > 1 {
            Divider()
            Button("Close All") {
                UIBridge.requiresConfirmation(
                    message: "Close everything open on \(title)?",
                    confirmTitle: "Close All",
                    destructive: true
                ) { confirmed in
                    if confirmed { AppRouter.shared.closeAll(owner) }
                }
            }
        }
    }
}
