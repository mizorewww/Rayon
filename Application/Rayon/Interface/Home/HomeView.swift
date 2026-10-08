//
//  HomeView.swift
//  Rayon (macOS)
//
//  Start page: status pills, title with counts, Quick Connect, the Servers grid with
//  Batch Startup, and Recent (servers and Quick Connect commands).
//

import MachineStatusView
import RayonModule
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var router = AppRouter.shared
    @ObservedObject var terminals = TerminalManager.shared
    @ObservedObject var monitors = MonitorCenter.shared
    @ObservedObject var forwards = PortForwardBackend.shared

    var body: some View {
        PageScaffold {
        } trailing: {
            ToolbarAction("New Server", systemImage: "plus", primary: true) {
                router.presentNewServer = true
            }
        } header: {
            VStack(alignment: .leading, spacing: RX.Space.s5) {
                PageTitle("Home")
                FactsRow([
                    .init("Servers", value: "\(store.machineGroup.count)"),
                    .init("Monitored", value: "\(monitors.sessions.count)"),
                    .init("Sessions", value: terminals.sessionContexts.isEmpty ? "None" : "\(terminals.sessionContexts.count) open"),
                    .init("Port forwards", value: forwards.container.isEmpty ? "None running" : "\(forwards.container.count) running"),
                ])
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                QuickConnectView()
                serversSection
                if store.storeRecent {
                    recentSection
                }
            }
        }
    }

    func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    // MARK: Servers

    var serversSection: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            SectionTitle("Servers", count: store.machineGroup.count) {
                if !store.machineGroup.machines.isEmpty {
                    Button {
                        router.batchStartup()
                    } label: {
                        Label("Batch Startup", systemImage: "wind")
                    }
                    .buttonStyle(.rx)
                    Button("View All") { router.route = .servers }
                        .buttonStyle(.rxPlain)
                }
            }
            if store.machineGroup.machines.isEmpty {
                EmptyStateView(
                    "No servers yet",
                    systemImage: "server.rack",
                    message: "Add a server to monitor it, open terminals and transfer files.",
                    actionTitle: "New Server"
                ) {
                    router.presentNewServer = true
                }
                .rxCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: RX.Space.s4)],
                    spacing: RX.Space.s4
                ) {
                    ForEach(store.machineGroup.machines) { machine in
                        ServerTile(machine: machine.id)
                    }
                    NewServerTile()
                }
            }
        }
        .padding(.top, RX.Space.s6)
    }

    // MARK: Recent

    var recentSection: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            SectionTitle("Recent") {
                if !store.recentRecord.isEmpty {
                    Button {
                        UIBridge.requiresConfirmation(
                            message: "Clear recent connections?",
                            informative: "Servers and saved commands are kept.",
                            confirmTitle: "Clear Recent",
                            destructive: true
                        ) { confirmed in
                            if confirmed { store.recentRecord = [] }
                        }
                    } label: {
                        Label("Clear Recent", systemImage: "trash")
                    }
                    .buttonStyle(.rxPlain)
                }
            }
            if store.recentRecord.isEmpty {
                HelpText("Servers you connect to and Quick Connect commands show up here.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rxCard()
            } else {
                RXDividedStack {
                    ForEach(store.recentRecord) { record in
                        RecentRow(record: record)
                    }
                }
                .rxCard(padding: RX.Space.s2)
            }
        }
        .padding(.top, RX.Space.s6)
    }
}

// MARK: - Quick Connect

/// Type `ssh user@host -p port` and press ⌘↩.
struct QuickConnectView: View {
    @EnvironmentObject var store: RayonStore
    @State private var command = ""
    @State private var suggestion: String?
    @FocusState private var focused: Bool

    /// Accepts the command with or without the leading `ssh`.
    var parsed: SSHCommandReader? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        return SSHCommandReader(command: trimmed) ?? SSHCommandReader(command: "ssh " + trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(spacing: RX.Space.s2) {
                Image(systemName: "terminal")
                    .font(.system(size: 15))
                    .foregroundStyle(.rxInkSecondary)
                TextField("ssh user@host -p 22", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .disableAutocorrection(true)
                    .focused($focused)
                    .onSubmit(connect)
                    .onChange(of: command) { newValue in
                        if newValue.hasPrefix("ssh ssh ") {
                            command.removeFirst("ssh ".count)
                        }
                        refreshSuggestion()
                    }
                KeyHint("↩")
                Button("Connect", action: connect)
                    .buttonStyle(.rxPrimary)
                    .disabled(parsed == nil)
            }
            .padding(.leading, RX.Space.s2)
            if let suggestion {
                Button {
                    command = suggestion
                } label: {
                    HStack(spacing: RX.Space.s2) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.rxInkSecondary)
                        Text("Did you mean ")
                            .foregroundColor(.rxInkSecondary)
                            + Text(suggestion).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            + Text("?").foregroundColor(.rxInkSecondary)
                        KeyHint("⌘↩")
                    }
                    .font(.rxBody)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .transition(.opacity)
            }
            HStack(spacing: RX.Space.s4) {
                Toggle("Record command", isOn: $store.saveTemporarySession)
                    .toggleStyle(.checkbox)
                    .font(.rxBody)
                    .foregroundStyle(.rxInkSecondary)
                Spacer()
                if store.identityGroupForAutoAuth.isEmpty {
                    HelpText("Quick Connect needs an identity that authenticates automatically.", isError: true)
                } else {
                    HelpText("Uses identities that authenticate automatically.")
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: suggestion)
        .rxCard()
    }

    func connect() {
        guard let parsed else { return }
        AppRouter.shared.openTerminal(command: parsed)
        command = ""
    }

    func refreshSuggestion() {
        guard command.count > 2 else {
            suggestion = nil
            return
        }
        suggestion = store.recentRecord
            .lazy
            .map(\.equivalentSSHCommand)
            .first { candidate in
                guard !candidate.isEmpty else { return false }
                let typed = command.hasPrefix("ssh ") ? command : "ssh " + command
                return candidate.hasPrefix(typed) && candidate != typed
            }
    }
}

// MARK: - Tiles

/// A server at a glance: name, address, state, CPU and memory while monitored.
/// Click opens the monitor, double-click a terminal, right-click the context menu.
struct ServerTile: View {
    let machine: RDMachine.ID
    @EnvironmentObject var store: RayonStore
    @State private var hovered = false

    var body: some View {
        let read = store.machineGroup[machine]
        ServerLiveReader(machine: machine) { state in
            VStack(alignment: .leading, spacing: RX.Space.s3) {
                HStack(alignment: .top, spacing: RX.Space.s2) {
                    VStack(alignment: .leading, spacing: 2) {
                        RedactableText(read.name, redacted: store.machineRedacted == .all)
                            .font(.rxBodyStrong)
                            .foregroundStyle(.rxInk)
                            .lineLimit(1)
                        RedactableText(read.remoteAddress, redacted: store.machineRedacted != .none)
                            .font(.rxCode)
                            .foregroundStyle(.rxInkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: RX.Space.s2)
                    StatusLabel(state.status, state.text)
                        .font(.system(size: 12))
                }
                if let cpu = state.cpu, let memory = state.memory {
                    tileBar("CPU", percent: cpu, color: .rxAccent)
                    tileBar("Memory", percent: memory, color: .rxSeries2)
                } else {
                    HStack {
                        CapsLabel("Last used")
                        Spacer()
                        Text(RXFormat.relative(read.lastConnection))
                            .font(.system(size: 12))
                            .foregroundStyle(.rxInkSecondary)
                    }
                    HStack {
                        CapsLabel("Group")
                        Spacer()
                        Text(read.group.isEmpty ? "Default" : read.group)
                            .font(.system(size: 12))
                            .foregroundStyle(.rxInkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .opacity(state.status == .danger ? 0.6 : 1)
        }
        .rxCard()
        .scaleEffect(hovered ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous))
        .onHover { hovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { AppRouter.shared.openTerminal(machine: machine) })
        .simultaneousGesture(TapGesture(count: 1).onEnded { AppRouter.shared.openMonitor(machine: machine) })
        .contextMenu { ServerContextMenu(machine: machine) }
        .help("Click for the monitor, double-click to open a terminal")
    }

    func tileBar(_ title: String, percent: Double, color: Color) -> some View {
        HStack(spacing: RX.Space.s2) {
            CapsLabel(title)
                .frame(width: 56, alignment: .leading)
            UsageBar(fraction: percent / 100, color: color)
            Text("\(RXFormat.percent(percent))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// The dashed tile that ends the server grid.
struct NewServerTile: View {
    @State private var hovered = false

    var body: some View {
        Button {
            AppRouter.shared.presentNewServer = true
        } label: {
            Label("New Server", systemImage: "plus")
                .font(.rxBody)
                .foregroundStyle(hovered ? Color.rxAccent : Color.rxInkSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(hovered ? Color.rxAccent : Color.rxControlBorder)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Recent

struct RecentRow: View {
    let record: RayonStore.RecentConnection
    @EnvironmentObject var store: RayonStore
    @State private var hovered = false

    var body: some View {
        HStack(spacing: RX.Space.s3) {
            switch record {
            case let .command(command):
                SymbolTile("terminal", size: 24, tinted: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.command)
                        .font(.rxCode)
                        .foregroundStyle(.rxInk)
                        .lineLimit(1)
                    Text("Quick Connect command")
                        .font(.rxHelp)
                        .foregroundStyle(.rxInkSecondary)
                }
            case let .machine(id):
                let machine = store.machineGroup[id]
                SymbolTile("server.rack", size: 24, tinted: false)
                VStack(alignment: .leading, spacing: 1) {
                    RedactableText(machine.isNotPlaceholder() ? machine.name : "Deleted server", redacted: store.machineRedacted == .all)
                        .font(.rxBody)
                        .foregroundStyle(.rxInk)
                        .lineLimit(1)
                    RedactableText(machine.remoteAddress, redacted: store.machineRedacted != .none)
                        .font(.rxHelp)
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: RX.Space.s2)
                Text(RXFormat.relative(machine.lastConnection))
                    .frame(minWidth: 80, alignment: .trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.rxInkSecondary)
            }
            Spacer(minLength: RX.Space.s2)
            Button("Connect", action: connect)
                .buttonStyle(.rx(size: .small))
        }
        .padding(.horizontal, RX.Space.s2)
        .frame(height: RX.tableRowHeight)
        .rxRowBackground(selected: false, hovered: hovered)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Connect", action: connect)
            Button("Copy Command") { UIBridge.sendPasteboard(str: record.equivalentSSHCommand) }
            Divider()
            Button("Remove from Recent", role: .destructive) {
                store.recentRecord.removeAll { $0.id == record.id }
            }
        }
    }

    func connect() {
        switch record {
        case let .command(command): AppRouter.shared.openTerminal(command: command)
        case let .machine(machine): AppRouter.shared.openTerminal(machine: machine)
        }
    }
}
