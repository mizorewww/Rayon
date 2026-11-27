//
//  ServersView+iOS.swift
//  Rayon
//
//  Servers in their folders, with redaction, folders, ssh_config import and
//  Batch Startup.
//

#if os(iOS)
    import MachineStatusView
    import RayonModule
    import SwiftUI

    struct ServersView: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject var monitors = MonitorCenter.shared
        @State private var searchKey = ""
        @State private var sshConfigSource: SSHConfigSource?

        var body: some View {
            Group {
                if store.machines.isEmpty, store.folders.isEmpty {
                    EmptyStateView(
                        "No servers yet",
                        systemImage: "server.rack",
                        actionTitle: "New Server"
                    ) {
                        ServerActions.create()
                    }
                    .frame(maxHeight: .infinity)
                    .background(RXBackdrop().ignoresSafeArea())
                } else {
                    List {
                        if redaction != .none {
                            Section {
                                HStack {
                                    Image(systemName: "eye.slash").foregroundStyle(.rxInkSecondary)
                                    Text(redaction == .all ? "Names and addresses are hidden" : "Addresses are hidden")
                                        .font(.subheadline)
                                        .foregroundStyle(.rxInkSecondary)
                                    Spacer()
                                    Button("Show") { redaction = .none }
                                        .font(.subheadline.weight(.semibold))
                                }
                                .rxListRow()
                            }
                        }
                        ForEach(store.serverGroups(matching: searchKey)) { group in
                            Section {
                                ForEach(group.machines) { machine in
                                    ServerListRow(machine: machine.id)
                                        .rxListRow()
                                }
                            } header: {
                                FolderHeader(name: group.name, count: group.machines.count)
                            }
                        }
                    }
                    .rxGroupedList()
                    .searchable(text: $searchKey, prompt: "Search servers")
                }
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Picker("Redaction", selection: $redaction) {
                            Label("Show Everything", systemImage: "eye").tag(RDMachine.RedactedLevel.none)
                            Label("Hide Addresses", systemImage: "eye.slash").tag(RDMachine.RedactedLevel.sensitive)
                            Label("Hide Names and Addresses", systemImage: "eye.slash.fill").tag(RDMachine.RedactedLevel.all)
                        }
                        Divider()
                        Button("New Folder…", systemImage: "folder.badge.plus") { FolderActions.newFolder() }
                        Button(UURemoteAccount.shared.isLoggedIn ? "UU Remote Account…" : "Link UU Remote Account…", systemImage: "link") {
                            FolderActions.linkUURemote()
                        }
                        SSHConfigImportMenuItems(source: $sshConfigSource)
                        Divider()
                        Button {
                            ServerActions.batchStartup()
                        } label: {
                            Label("Batch Startup", systemImage: "wind")
                        }
                        .disabled(store.machines.isEmpty)
                    } label: {
                        Label("More", systemImage: redaction == .none ? "ellipsis.circle" : "eye.slash")
                    }
                    Button {
                        ServerActions.create()
                    } label: {
                        Label("New Server", systemImage: "plus")
                    }
                }
            }
            .sshConfigImporter($sshConfigSource)
        }
    }

    /// A server row: name, address, state. A tap goes into the server's
    /// terminal; its actions are in the ⋯ menu and on a long press.
    struct ServerListRow: View {
        let machine: RDMachine.ID
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject var monitors = MonitorCenter.shared

        var body: some View {
            let read = (store.machine(machine) ?? RDMachine())
            Button {
                ServerActions.openTerminal(machine)
            } label: {
                HStack(spacing: RX.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        RedactableText(read.name, redacted: redaction == .all)
                            .foregroundStyle(.rxInk)
                            .lineLimit(1)
                        if read.isUURemoteDevice {
                            Text("UU Remote")
                                .font(.footnote)
                                .foregroundStyle(.rxInkSecondary)
                        } else {
                            RedactableText(read.displayAddress, redacted: redaction != .none)
                                .font(.rxCode)
                                .foregroundStyle(.rxInkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if let session = monitors.session(for: machine) {
                        ServerRowState(session: session)
                    } else {
                        Text(RXFormat.relative(read.lastConnection))
                            .font(.footnote)
                            .foregroundStyle(.rxInkSecondary)
                    }
                    Menu {
                        ServerContextMenu(machine: machine)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.rxInkSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Actions")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { ServerContextMenu(machine: machine) }
            .swipeActions {
                Button(role: .destructive) {
                    ServerActions.delete([machine])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    ServerActions.edit(machine)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.rxAccent)
            }
        }
    }

    private struct ServerRowState: View {
        @ObservedObject var session: MonitorSession
        var body: some View {
            VStack(alignment: .trailing, spacing: 2) {
                if session.status.hasData {
                    Text("CPU \(RXFormat.percent(Double(session.status.processor.summary.sumUsed)))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.rxInkSecondary)
                }
            }
        }
    }

#endif
