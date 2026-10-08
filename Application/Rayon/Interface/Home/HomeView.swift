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

    var body: some View {
        ScrollView {
            VStack(spacing: RX.Space.s6) {
                QuickConnectHero()
                    .padding(.top, 72)
                    .padding(.bottom, RX.Space.s6)
                serversSection
            }
            .padding(.horizontal, RX.Space.s6)
            .padding(.bottom, RX.Space.s6)
            .frame(maxWidth: .infinity)
        }
        .pageChrome()
        .pageToolbar {
        } trailing: {
            ToolbarAction("Batch Startup", systemImage: "wind") { router.batchStartup() }
                .disabled(store.machineGroup.machines.isEmpty)
            ToolbarAction("New Server", systemImage: "plus", primary: true) {
                router.presentNewServer = true
            }
        }
    }

    @ViewBuilder var serversSection: some View {
        if !store.machineGroup.machines.isEmpty {
            VStack(alignment: .leading, spacing: RX.Space.s3) {
                SectionTitle("Servers") {
                    Button("View All") { router.route = .servers }
                        .buttonStyle(.rxPlain)
                }
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
    }
}

// MARK: - Quick Connect

/// The big, fast way in: type `user@host` and press Return. Focused on open.
struct QuickConnectHero: View {
    @EnvironmentObject var store: RayonStore
    @State private var command = ""
    @State private var suggestion: String?
    @FocusState private var focused: Bool

    var parsed: SSHCommandReader? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        return SSHCommandReader(command: trimmed) ?? SSHCommandReader(command: "ssh " + trimmed)
    }

    var body: some View {
        VStack(spacing: RX.Space.s4) {
            HStack(spacing: RX.Space.s3) {
                Image(systemName: "terminal")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.rxInkSecondary)
                TextField("ssh user@host -p 22", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .disableAutocorrection(true)
                    .focused($focused)
                    .onSubmit(connect)
                    .onChange(of: command) { newValue in
                        if newValue.hasPrefix("ssh ssh ") { command.removeFirst("ssh ".count) }
                        refreshSuggestion()
                    }
                Button(action: connect) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.rxOnAccent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.rxAccent))
                }
                .buttonStyle(.plain)
                .disabled(parsed == nil)
                .opacity(parsed == nil ? 0.35 : 1)
                .accessibilityLabel("Connect")
            }
            .padding(.leading, RX.Space.s5)
            .padding(.trailing, RX.Space.s2)
            .frame(height: 64)
            .background(
                Capsule()
                    .fill(.thickMaterial)
                    .overlay(Capsule().fill(Color.rxSurface.opacity(0.35)))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            )
            .frame(maxWidth: 640)

            if let suggestion {
                Button {
                    command = suggestion
                    connect()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                        Text(suggestion).font(.system(size: 13, design: .monospaced))
                        KeyHint("⌘↩")
                    }
                    .foregroundStyle(.rxInkSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }

            if store.identityGroupForAutoAuth.isEmpty {
                Text("Needs an identity that authenticates automatically.")
                    .font(.rxHelp)
                    .foregroundStyle(.rxWarning)
            }

            if store.storeRecent, !store.recentRecord.isEmpty {
                RXFlowLayout(spacing: RX.Space.s2, alignment: .center) {
                    ForEach(store.recentRecord) { record in
                        RecentChip(record: record)
                    }
                }
                .frame(maxWidth: 640)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            onMainThread(delay: 0.2) { focused = true }
        }
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
        let typed = command.hasPrefix("ssh ") ? command : "ssh " + command
        suggestion = store.recentRecord
            .lazy
            .map(\.equivalentSSHCommand)
            .first { !$0.isEmpty && $0.hasPrefix(typed) && $0 != typed }
    }
}

/// A recent server or command; one click connects.
struct RecentChip: View {
    let record: RayonStore.RecentConnection
    @EnvironmentObject var store: RayonStore
    @State private var hovered = false

    var title: String {
        switch record {
        case let .command(command): return command.command.replacingOccurrences(of: "ssh ", with: "")
        case let .machine(id):
            let machine = store.machineGroup[id]
            return machine.isNotPlaceholder() ? machine.name : "Deleted server"
        }
    }

    var body: some View {
        Button(action: connect) {
            HStack(spacing: 6) {
                Image(systemName: isCommand ? "terminal" : "server.rack")
                    .font(.system(size: 11))
                RedactableText(title, redacted: !isCommand && store.machineRedacted == .all)
                    .font(.system(size: 12, design: isCommand ? .monospaced : .default))
                    .lineLimit(1)
            }
            .foregroundStyle(.rxInk)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(hovered ? 0.12 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Copy Command") { UIBridge.sendPasteboard(str: record.equivalentSSHCommand) }
            Divider()
            Button("Remove from Recent", role: .destructive) {
                store.recentRecord.removeAll { $0.id == record.id }
            }
        }
    }

    var isCommand: Bool {
        if case .command = record { return true }
        return false
    }

    func connect() {
        switch record {
        case let .command(command): AppRouter.shared.openTerminal(command: command)
        case let .machine(machine): AppRouter.shared.openTerminal(machine: machine)
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

                }
            }
        }
        .rxCard()
        .scaleEffect(hovered ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous))
        .onHover { hovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { AppRouter.shared.openTerminal(machine: machine) })
        .simultaneousGesture(TapGesture(count: 1).onEnded { AppRouter.shared.openMonitor(machine: machine) })
        .contextMenu { ServerContextMenu(machine: machine) }
        .help("Double-click to open a terminal")
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
