//
//  ServersView.swift
//  Rayon (macOS)
//
//  All servers grouped, with search, redaction, Open Terminals and New Server.
//

import MachineStatusView
import RayonModule
import SwiftUI

struct ServersView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var router = AppRouter.shared

    @State private var searchText = ""
    @State private var selection: RDMachine.ID?

    var filtered: [RDMachine] {
        let machines = store.machineGroup.machines
        guard !searchText.isEmpty else { return machines }
        return machines.filter { $0.isQualifiedForSearch(text: searchText.lowercased()) }
    }

    var groups: [(name: String, machines: [RDMachine])] {
        let machines = filtered
        let names = Set(machines.map(\.group)).sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return names.map { name in
            (name, machines.filter { $0.group == name }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    var body: some View {
        PageScaffold(search: $searchText, searchPrompt: "Search servers") {
        } trailing: {
            RedactionMenu()
            Button { router.openTerminals() } label: {
                Label("Open Terminals…", systemImage: "rectangle.stack.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .help("Pick several servers and open a terminal on each")
                .disabled(store.machineGroup.machines.isEmpty)
            ToolbarAction("New Server", systemImage: "plus", primary: true) {
                router.presentNewServer = true
            }
        } header: {
            VStack(alignment: .leading, spacing: RX.Space.s3) {
                PageTitle("Servers")
                if store.machineRedacted != .none {
                    RedactionBanner()
                }
            }
        } content: {
            if store.machineGroup.machines.isEmpty {
                EmptyStateView(
                    "No servers yet",
                    systemImage: "server.rack",
                    actionTitle: "New Server"
                ) {
                    router.presentNewServer = true
                }
                .rxCard()
            } else if filtered.isEmpty {
                EmptyStateView("No matches", systemImage: "magnifyingglass")
                .rxCard()
            } else {
                ServersTable(groups: groups, selection: $selection)
            }
        }
        .background {
            // ⌘⌫ deletes the selected row.
            Button("Delete") {
                if let selection { ServerActions.delete([selection]) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selection == nil)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}

/// None → Sensitive hides addresses → All hides names too.
struct RedactionMenu: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        Menu {
            Picker("Redaction", selection: $store.machineRedacted) {
                Label("Show Everything", systemImage: "eye").tag(RDMachine.RedactedLevel.none)
                Label("Hide Addresses", systemImage: "eye.slash").tag(RDMachine.RedactedLevel.sensitive)
                Label("Hide Names and Addresses", systemImage: "eye.slash.fill").tag(RDMachine.RedactedLevel.all)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Privacy", systemImage: store.machineRedacted == .none ? "eye" : "eye.slash")
                .labelStyle(.titleAndIcon)
        }
        .menuIndicator(.hidden)
        .help(store.machineRedacted.tooltip)
        .keyboardShortcut("h", modifiers: .option)
    }
}

/// States that details are hidden and offers the way back.
struct RedactionBanner: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        HStack(spacing: RX.Space.s2) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.rxInkSecondary)
            Text(store.machineRedacted == .all ? "Names and addresses hidden" : "Addresses hidden")
                .font(.rxBody)
                .foregroundStyle(.rxInkSecondary)
            Button("Show") { store.machineRedacted = .none }
                .buttonStyle(.rx(size: .small))
        }
        .padding(.horizontal, 12)
        .frame(height: RX.controlHeight)
        .background(Capsule().fill(Color.rxPill))
    }
}

// MARK: - Table

private struct ServersTable: View {
    let groups: [(name: String, machines: [RDMachine])]
    @Binding var selection: RDMachine.ID?
    @State private var width: CGFloat = 900

    var body: some View {
        let columns = ServerColumns(width: width)
        VStack(spacing: 0) {
            header(columns)
            Hairline()
            ForEach(groups, id: \.name) { group in
                TableGroupRow(group.name.isEmpty ? "Default" : group.name, trailing: "\(group.machines.count)")
                ForEach(group.machines) { machine in
                    ServerRow(machine: machine.id, columns: columns, selection: $selection)
                }
            }
        }
        .readWidth($width)
        .rxCard(padding: RX.Space.s2)
    }

    func header(_ columns: ServerColumns) -> some View {
        HStack(spacing: 0) {
            TableHeaderLabel("Name").frame(maxWidth: .infinity, alignment: .leading)
            TableHeaderLabel("Address").frame(width: columns.address)
            if columns.showIdentity { TableHeaderLabel("Identity").frame(width: columns.identity) }
            if columns.showCPU { TableHeaderLabel("CPU").frame(width: columns.cpu) }
            if columns.showLastUsed { TableHeaderLabel("Last used").frame(width: columns.lastUsed) }
            Color.clear.frame(width: columns.actions, height: 1)
        }
        .padding(.horizontal, RX.Space.s3)
        .frame(height: RX.tableHeaderHeight)
    }
}

struct ServerColumns {
    let address: CGFloat = 150
    let identity: CGFloat = 110
    let cpu: CGFloat = 110
    let lastUsed: CGFloat = 120
    let actions: CGFloat = 220
    let showIdentity: Bool
    let showCPU: Bool
    let showLastUsed: Bool

    init(width: CGFloat) {
        let base: CGFloat = 180 + 150 + 220 + 24
        showCPU = width > base + 110
        showIdentity = width > base + 110 + 110
        showLastUsed = width > base + 110 + 110 + 120
    }
}

private struct ServerRow: View {
    let machine: RDMachine.ID
    let columns: ServerColumns
    @Binding var selection: RDMachine.ID?

    @EnvironmentObject var store: RayonStore
    @State private var hovered = false

    var body: some View {
        let read = store.machineGroup[machine]
        ServerLiveReader(machine: machine) { state in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    RedactableText(read.name, redacted: store.machineRedacted == .all)
                        .font(.rxBody)
                        .foregroundStyle(.rxInk)
                        .lineLimit(1)
                    if !read.comment.isEmpty, store.machineRedacted == .none {
                        Text(read.comment)
                            .font(.rxHelp)
                            .foregroundStyle(.rxInkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RedactableText(read.remoteAddress, redacted: store.machineRedacted != .none)
                    .font(.rxCode)
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: columns.address, alignment: .leading)
                if columns.showIdentity {
                    Text(identityName(read))
                        .font(.rxBody)
                        .foregroundStyle(read.associatedIdentity == nil ? Color.rxInkSecondary : Color.rxInk)
                        .lineLimit(1)
                        .frame(width: columns.identity, alignment: .leading)
                }
                if columns.showCPU {
                    Group {
                        if let cpu = state.cpu {
                            HStack(spacing: RX.Space.s2) {
                                UsageBar(fraction: cpu / 100, height: 4)
                                    .frame(width: 48)
                                Text("\(RXFormat.percent(cpu))%")
                                    .font(.rxBody.monospacedDigit())
                            }
                        } else {
                            Text("—").foregroundStyle(.rxInkSecondary)
                        }
                    }
                    .frame(width: columns.cpu, alignment: .leading)
                }
                if columns.showLastUsed {
                    Text(RXFormat.relative(read.lastConnection))
                        .font(.rxBody)
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                        .frame(width: columns.lastUsed, alignment: .leading)
                }
                HStack(spacing: RX.Space.s1) {
                    ForEach([ServerTool.files, .monitor]) { tool in
                        Button(tool.title) { tool.show(machine) }
                            .buttonStyle(.rx(.plain, size: .small))
                            .help(tool.help)
                    }
                    Button("Connect") { AppRouter.shared.openTerminal(machine: machine) }
                        .buttonStyle(.rx(size: .small))
                        .help(ServerTool.terminal.help)
                }
                .frame(width: columns.actions, alignment: .trailing)
            }
        }
        .padding(.horizontal, RX.Space.s3)
        .frame(height: RX.tableRowHeight)
        .rxRowBackground(selected: selection == machine, hovered: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { AppRouter.shared.openTerminal(machine: machine) })
        .simultaneousGesture(TapGesture(count: 1).onEnded { selection = machine })
        .contextMenu { ServerContextMenu(machine: machine) }
    }

    func identityName(_ machine: RDMachine) -> String {
        guard let aid = machine.associatedIdentity, let uid = UUID(uuidString: aid) else { return "Automatic" }
        let identity = store.identityGroup[uid]
        return identity.username.isEmpty ? "Missing" : identity.username
    }
}
