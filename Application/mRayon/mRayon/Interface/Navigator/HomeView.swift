//
//  HomeView.swift
//  mRayon
//
//  Home: Quick Connect, server tiles, Recent.
//

import MachineStatusView
import RayonModule
import SwiftUI

private var importData: Data?

struct HomeView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var monitors = MonitorCenter.shared
    @State private var openNewServer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RX.Space.s6) {
                QuickConnectCard()
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    SectionTitle("Servers", count: store.machineGroup.count) {
                        if !store.machineGroup.machines.isEmpty {
                            Button {
                                ServerActions.batchStartup()
                            } label: {
                                Label("Batch Startup", systemImage: "wind")
                            }
                            .buttonStyle(.rx(size: .small))
                        }
                    }
                    if store.machineGroup.machines.isEmpty {
                        EmptyStateView(
                            "No servers yet",
                            systemImage: "server.rack",
                            message: "Add a server to monitor it, open terminals and transfer files.",
                            actionTitle: "New Server"
                        ) {
                            openNewServer = true
                        }
                        .rxCard()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: RX.Space.s3)], spacing: RX.Space.s3) {
                            ForEach(store.machineGroup.machines) { machine in
                                ServerTile(machine: machine.id)
                            }
                        }
                    }
                }
                if store.storeRecent, !store.recentRecord.isEmpty {
                    VStack(alignment: .leading, spacing: RX.Space.s3) {
                        SectionTitle("Recent") {
                            Button("Clear") {
                                UIBridge.requiresConfirmation(message: "Clear recent connections?") { confirmed in
                                    if confirmed { store.recentRecord = [] }
                                }
                            }
                            .buttonStyle(.rx(.plain, size: .small))
                        }
                        RXDividedStack {
                            ForEach(store.recentRecord) { record in
                                RecentRow(record: record)
                            }
                        }
                        .rxCard(padding: RX.Space.s2)
                    }
                }
                Text(appVersion)
                    .font(.rxHelp)
                    .foregroundStyle(.rxInkTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(RX.Space.s4)
        }
        .background(RXBackdrop().ignoresSafeArea())
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem {
                Button {
                    openNewServer = true
                } label: {
                    Label("New Server", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $openNewServer) {
            NavigationStack { EditMachineView() }
        }
    }
}

/// Type `ssh user@host -p port` and connect. Uses identities that authenticate automatically.
struct QuickConnectCard: View {
    @EnvironmentObject var store: RayonStore
    @State private var command = ""
    @State private var suggestion: String?

    var parsed: SSHCommandReader? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        return SSHCommandReader(command: trimmed) ?? SSHCommandReader(command: "ssh " + trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            CardHead("Quick Connect")
            HStack(spacing: RX.Space.s2) {
                TextField("ssh user@host -p 22", text: $command)
                    .font(.system(size: 15, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .onChange(of: command) { newValue in
                        if newValue.hasPrefix("ssh ssh ") { command.removeFirst("ssh ".count) }
                        refreshSuggestion()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .rxFieldBackground()
                Button("Connect", action: connect)
                    .buttonStyle(.rxPrimary)
                    .disabled(parsed == nil)
                    .simultaneousGesture(LongPressGesture().onEnded { _ in importFromPasteboard() })
            }
            if let suggestion {
                Button {
                    command = suggestion
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb")
                        Text(suggestion).font(.system(size: 13, design: .monospaced)).lineLimit(1)
                    }
                    .foregroundStyle(.rxAccent)
                }
            }
            HStack {
                Toggle("Record command", isOn: $store.saveTemporarySession)
                    .font(.subheadline)
                    .tint(.rxAccent)
            }
            HelpText(store.identityGroupForAutoAuth.isEmpty
                ? "Quick Connect needs an identity that authenticates automatically."
                : "Uses identities that authenticate automatically.",
                isError: store.identityGroupForAutoAuth.isEmpty)
        }
        .rxCard()
    }

    func connect() {
        guard let parsed else { return }
        TerminalManager.shared.begin(for: parsed)
        command = ""
    }

    func refreshSuggestion() {
        guard command.count > 2 else {
            suggestion = nil
            return
        }
        let typed = command.hasPrefix("ssh ") ? command : "ssh " + command
        suggestion = store.recentRecord.lazy.map(\.equivalentSSHCommand).first {
            !$0.isEmpty && $0.hasPrefix(typed) && $0 != typed
        }
    }

    /// Hidden importer kept from the original app: long-press Connect with the
    /// exported data, then again with its key, on the pasteboard.
    func importFromPasteboard() {
        guard let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        if let data = importData {
            importData = nil
            RayonStore.overrideImport(from: data, key: paste)
        } else if let data = Data(base64Encoded: paste) {
            importData = data
        }
    }
}

/// A server at a glance: name, address, state, CPU and memory while monitored.
struct ServerTile: View {
    let machine: RDMachine.ID
    @EnvironmentObject var store: RayonStore
    @ObservedObject var monitors = MonitorCenter.shared

    var body: some View {
        let read = store.machineGroup[machine]
        Menu {
            ServerMenuItems(machine: machine)
        } label: {
            VStack(alignment: .leading, spacing: RX.Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        RedactableText(read.name, redacted: store.machineRedacted == .all)
                            .font(.headline)
                            .foregroundStyle(.rxInk)
                            .lineLimit(1)
                        RedactableText(read.remoteAddress, redacted: store.machineRedacted != .none)
                            .font(.rxCode)
                            .foregroundStyle(.rxInkSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let session = monitors.session(for: machine) {
                        LiveTileState(session: session)
                    } else {
                        StatusLabel(.off, "Not monitored")
                            .font(.footnote)
                    }
                }
                if let session = monitors.session(for: machine) {
                    LiveTileBars(session: session)
                } else {
                    HStack {
                        CapsLabel("Last used")
                        Spacer()
                        Text(RXFormat.relative(read.lastConnection))
                            .font(.footnote)
                            .foregroundStyle(.rxInkSecondary)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .rxCard()
        }
        .buttonStyle(.plain)
    }
}

private struct LiveTileState: View {
    @ObservedObject var session: MonitorSession
    var body: some View {
        StatusLabel(session.health.status, session.health.text)
            .font(.footnote)
    }
}

private struct LiveTileBars: View {
    @ObservedObject var session: MonitorSession
    var body: some View {
        let cpu = Double(session.status.processor.summary.sumUsed)
        let memory = session.status.memoryUsedPercent
        VStack(spacing: RX.Space.s2) {
            bar("CPU", cpu, .rxAccent)
            bar("Memory", memory, .rxSeries2)
        }
    }

    func bar(_ title: String, _ percent: Double, _ color: Color) -> some View {
        HStack(spacing: RX.Space.s2) {
            CapsLabel(title).frame(width: 56, alignment: .leading)
            UsageBar(fraction: percent / 100, color: color)
            Text("\(RXFormat.percent(percent))%")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}

struct RecentRow: View {
    let record: RayonStore.RecentConnection
    @EnvironmentObject var store: RayonStore

    var body: some View {
        Button(action: connect) {
            HStack(spacing: RX.Space.s3) {
                switch record {
                case let .command(command):
                    SymbolTile("terminal", size: 28, tinted: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(command.command).font(.rxCode).foregroundStyle(.rxInk).lineLimit(1)
                        Text("Quick Connect command").font(.caption).foregroundStyle(.rxInkSecondary)
                    }
                case let .machine(id):
                    let machine = store.machineGroup[id]
                    SymbolTile("server.rack", size: 28, tinted: false)
                    VStack(alignment: .leading, spacing: 1) {
                        RedactableText(machine.isNotPlaceholder() ? machine.name : "Deleted server", redacted: store.machineRedacted == .all)
                            .foregroundStyle(.rxInk)
                            .lineLimit(1)
                        RedactableText(machine.remoteAddress, redacted: store.machineRedacted != .none)
                            .font(.caption)
                            .foregroundStyle(.rxInkSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.rxInkTertiary)
            }
            .padding(.horizontal, RX.Space.s2)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Command") { UIBridge.sendPasteboard(str: record.equivalentSSHCommand) }
            Button("Remove from Recent", role: .destructive) {
                store.recentRecord.removeAll { $0.id == record.id }
            }
        }
    }

    func connect() {
        switch record {
        case let .command(command): TerminalManager.shared.begin(for: command)
        case let .machine(machine): TerminalManager.shared.begin(for: machine)
        }
    }
}
