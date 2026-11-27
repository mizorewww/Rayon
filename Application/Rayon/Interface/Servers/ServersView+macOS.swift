//
//  ServersView+macOS.swift
//  Rayon
//
//  All servers in a Table, a section per folder: sortable columns that can
//  be hidden, several selected at once for Open Terminals, Move to Folder
//  and Delete, a double click or Return for a terminal; search, redaction,
//  Open Terminals… and New Server.
//

#if os(macOS)
    import MachineStatusView
    import RayonDesign
    import RayonModule
    import SwiftUI

    struct ServersView: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject var router = AppRouter.shared
        /// The toolbar names the account item by whether one is signed in.
        @ObservedObject private var account = UURemoteAccount.shared

        @State private var searchText = ""
        @State private var selection = Set<RDMachine.ID>()
        @State private var sortOrder = [KeyPathComparator(\RDMachine.name, comparator: .localizedStandard)]

        var body: some View {
            PageScaffold(
                scrolls: false,
                search: $searchText,
                searchPrompt: "Search servers",
                primary: ToolbarAction("New Server", systemImage: "plus", primary: true) {
                    ServerActions.create()
                }
            ) {
            } trailing: {
                RXToolbarMenu(
                    "New Folder",
                    systemImage: "folder.badge.plus",
                    items: [
                        RXToolbarMenuItem("New Folder…", systemImage: "folder.badge.plus", isOn: false) { FolderActions.newFolder() },
                        RXToolbarMenuItem("Import ~/.ssh/config…", systemImage: "square.and.arrow.down", isOn: false) { importSSHConfigFromToolbar() },
                        RXToolbarMenuItem(account.isLoggedIn ? "UU Remote Account…" : "Link UU Remote Account…", systemImage: "link", isOn: false) { FolderActions.linkUURemote() },
                    ]
                )
                .help("Make a folder, or fill one from a UU Remote account")
                RedactionMenu()
                Button { router.openTerminals() } label: {
                    Label("Open Terminals…", systemImage: "rectangle.stack.badge.plus")
                }
                .help("Pick several servers and open a terminal on each")
                .disabled(store.machines.isEmpty)
            } header: {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    PageTitle("Servers")
                    if redaction != .none {
                        RedactionBanner()
                    }
                }
            } content: {
                if store.machines.isEmpty, store.folders.isEmpty {
                    EmptyStateView(
                        "No servers yet",
                        systemImage: "server.rack",
                        actionTitle: "New Server"
                    ) {
                        ServerActions.create()
                    }
                    .rxCard()
                } else {
                    ServersTable(groups: store.serverGroups(matching: searchText, sortedBy: sortOrder), selection: $selection, sortOrder: $sortOrder)
                        .overlay {
                            if !searchText.isEmpty, !store.machines.contains(where: { $0.isQualifiedForSearch(text: searchText) }) {
                                ContentUnavailableView.search(text: searchText)
                            }
                        }
                }
            }
            // Edit › Delete… (⌘⌫) deletes the selected rows.
            .focusedSceneValue(\.deleteSelection, selection.isEmpty ? nil : { ServerActions.delete(Array(selection)) })
        }

        private func importSSHConfigFromToolbar() {
            let sshDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
            OpenPanel.present(
                message: "Choose an OpenSSH config file (e.g. ~/.ssh/config)",
                prompt: "Import",
                directory: sshDir,
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: false,
                canCreateDirectories: false,
                showsHiddenFiles: true
            ) { urls in
                guard let url = urls.first else { return }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    Indicator.error(String(localized: "Could not read \(url.lastPathComponent) as UTF-8 text."))
                    return
                }
                _ = store.importOpenSSHConfig(text, baseDirectory: url.deletingLastPathComponent())
            }
        }
    }

    /// None → Sensitive hides addresses → All hides names too.
    struct RedactionMenu: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction

        var body: some View {
            RXToolbarMenu(
                "Privacy",
                systemImage: redaction == .none ? "eye" : "eye.slash",
                items: [
                    item("Show Everything", systemImage: "eye", level: .none),
                    item("Hide Addresses", systemImage: "eye.slash", level: .sensitive),
                    item("Hide Names and Addresses", systemImage: "eye.slash.fill", level: .all),
                ]
            )
            .help(redaction.tooltip)
        }

        private func item(_ title: LocalizedStringResource, systemImage: String, level: RDMachine.RedactedLevel) -> RXToolbarMenuItem {
            RXToolbarMenuItem(title, systemImage: systemImage, isOn: redaction == level) {
                redaction = level
            }
        }
    }

    /// States that details are hidden and offers the way back.
    struct RedactionBanner: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction

        var body: some View {
            HStack(spacing: RX.Space.s2) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.rxInkSecondary)
                Text(redaction == .all ? "Names and addresses hidden" : "Addresses hidden")
                    .font(.rxBody)
                    .foregroundStyle(.rxInkSecondary)
                Button("Show") { redaction = .none }
                    .buttonStyle(.rx(size: .small))
            }
            .padding(.horizontal, 12)
            .frame(height: RX.controlHeight)
            .background(Capsule().fill(Color.rxPill))
        }
    }

    // MARK: - Table

    private struct ServersTable: View {
        let groups: [ServerGroup]
        @Binding var selection: Set<RDMachine.ID>
        @Binding var sortOrder: [KeyPathComparator<RDMachine>]
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        /// Which columns are shown, their order and widths.
        @SceneStorage("ServersTableColumns") private var columns = TableColumnCustomization<RDMachine>()

        var body: some View {
            Table(of: RDMachine.self, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
                TableColumn("Name", value: \.name, comparator: .localizedStandard) { machine in
                    VStack(alignment: .leading, spacing: 1) {
                        RedactableText(machine.name, redacted: redaction == .all)
                            .lineLimit(1)
                        if !machine.comment.isEmpty, redaction == .none {
                            Text(machine.comment)
                                .font(.rxHelp)
                                .foregroundStyle(.rxInkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .width(min: 120, ideal: 180)
                .customizationID("name")
                TableColumn("Address", value: \.remoteAddress, comparator: .localizedStandard) { machine in
                    if machine.isUURemoteDevice {
                        UUDeviceStatus(machine: machine)
                    } else {
                        RedactableText(machine.displayAddress, redacted: redaction != .none)
                            .font(.rxCode)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .width(min: 100, ideal: 150)
                .customizationID("address")
                TableColumn("Identity") { machine in
                    Text(identityName(machine))
                        .foregroundStyle(machine.associatedIdentity == nil ? Color.rxInkSecondary : Color.rxInk)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110)
                .customizationID("identity")
                TableColumn("CPU") { machine in
                    ServerLiveReader(machine: machine.id) { state in
                        if let cpu = state.cpu {
                            HStack(spacing: RX.Space.s2) {
                                ProgressView(value: min(max(cpu / 100, 0), 1))
                                    .frame(width: 48)
                                Text("\(RXFormat.percent(cpu))%")
                                    .monospacedDigit()
                            }
                        } else {
                            Text("—").foregroundStyle(.rxInkSecondary)
                        }
                    }
                }
                .width(min: 60, ideal: 110)
                .customizationID("cpu")
                TableColumn("Last used", value: \.lastConnection) { machine in
                    Text(RXFormat.relative(machine.lastConnection))
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                }
                .width(min: 70, ideal: 120)
                .customizationID("lastUsed")
                TableColumn("Tools") { machine in
                    // Words where they fit beside Terminal, icons where not.
                    UUReachable(machine: machine) {
                        ViewThatFits(in: .horizontal) {
                            ServerToolButtons(machine: machine, iconOnly: false)
                            ServerToolButtons(machine: machine, iconOnly: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 150, ideal: 300)
                .customizationID("tools")
            } rows: {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.machines) { TableRow($0) }
                    } header: {
                        FolderHeader(name: group.name, count: group.machines.count)
                    }
                }
            }
            .contextMenu(forSelectionType: RDMachine.ID.self) { chosen in
                if chosen.count == 1, let machine = chosen.first {
                    ServerContextMenu(machine: machine)
                } else if !chosen.isEmpty {
                    let machines = store.machines.map(\.id).filter(chosen.contains)
                    Button("Open \(machines.count) Terminals", systemImage: ServerTool.terminal.systemImage) {
                        for machine in machines { AppRouter.shared.openTerminal(machine: machine) }
                    }
                    MoveToFolderMenu(machines: machines)
                    Section {
                        Button("Delete \(machines.count) Servers…", systemImage: "trash", role: .destructive) {
                            ServerActions.delete(machines)
                        }
                    }
                }
            } primaryAction: { chosen in
                for machine in chosen { ServerTool.terminal.show(machine) }
            }
        }

        private func identityName(_ machine: RDMachine) -> String {
            guard let uid = machine.associatedIdentity else {
                // The server's own user name, tried with each automatic identity.
                return machine.sshUsernameOverride.map { String(localized: "\($0) · Automatic") } ?? String(localized: "Automatic")
            }
            let identity = (store.identity(uid) ?? RDIdentity())
            return identity.username.isEmpty ? String(localized: "Missing") : machine.sshLoginUsername(identity: identity)
        }
    }

    /// Terminal as a word, then Files, Monitor (and Desktop) as words or icons.
    private struct ServerToolButtons: View {
        let machine: RDMachine
        let iconOnly: Bool

        var body: some View {
            HStack(spacing: RX.Space.s1) {
                Button(ServerTool.terminal.title) { ServerTool.terminal.show(machine.id) }
                    .buttonStyle(.rx(size: .small))
                    .help(ServerTool.terminal.help(for: machine))
                let others: [ServerTool] = machine.hasRemoteDesktop ? [.files, .monitor, .desktop] : [.files, .monitor]
                ForEach(others) { tool in
                    Button { tool.show(machine.id) } label: {
                        Label(tool.title, systemImage: tool.systemImage)
                            .labelStyle(TitleOrIcon(iconOnly: iconOnly))
                    }
                    .buttonStyle(.rx(.plain, size: .small, iconOnly: iconOnly))
                    .help(tool.help(for: machine))
                    .accessibilityLabel(tool.title)
                }
            }
            .fixedSize()
        }
    }

    /// Where a UU device is, in the Address column: on UU Remote, and whether
    /// it was online at the last refresh.
    private struct UUDeviceStatus: View {
        let machine: RDMachine
        @ObservedObject private var account = UURemoteAccount.shared

        var body: some View {
            let device = account.devices.first { $0.deviceID == machine.uuDeviceID }
            HStack(spacing: RX.Space.s2) {
                StatusDot(device.map { $0.isOnline ? .success : .off } ?? .off, size: .small)
                Text(device.map { $0.isOnline ? "UU Remote · Online" : "UU Remote · Offline" } ?? "UU Remote")
                    .foregroundStyle(device?.isOnline == true ? Color.rxInk : Color.rxInkSecondary)
                    .lineLimit(1)
            }
        }
    }

    /// A UU device's tools, off while it cannot be reached: signed out of the
    /// account, or offline in it. Any other server's, as they are.
    private struct UUReachable<Content: View>: View {
        let machine: RDMachine
        @ViewBuilder let content: Content
        @ObservedObject private var account = UURemoteAccount.shared

        var body: some View {
            if machine.isUURemoteDevice {
                let device = account.devices.first { $0.deviceID == machine.uuDeviceID }
                content.disabled(!account.isLoggedIn || device?.isOnline == false)
            } else {
                content
            }
        }
    }

    /// A label as words, or as its icon where room is short.
    private struct TitleOrIcon: LabelStyle {
        let iconOnly: Bool

        func makeBody(configuration: Configuration) -> some View {
            if iconOnly { configuration.icon } else { configuration.title }
        }
    }

#endif
