//
//  PortForwardView+macOS.swift
//  Rayon
//
//  Forwards: orientation, bind, through server, target, status and an on/off switch.
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    /// Header and rows share these, so the columns line up.
    private enum ForwardColumns {
        static let orientation: CGFloat = 115
        static let bind: CGFloat = 80
        static let status: CGFloat = 95
        static let toggle: CGFloat = 52
    }

    struct PortForwardView: View {
        @EnvironmentObject var store: RayonStore
        @ObservedObject var backend = PortForwardBackend.shared

        @State private var searchText = ""
        @State private var selection: RDPortForward.ID?
        @State private var editor: EditorTarget?

        struct EditorTarget: Identifiable {
            let id = UUID()
            let forward: RDPortForward.ID?
        }

        var filtered: [RDPortForward] {
            let all = store.portForwards
            guard !searchText.isEmpty else { return all }
            let key = searchText.lowercased()
            return all.filter {
                $0.targetHost.lowercased().contains(key)
                    || String($0.targetPort).contains(key)
                    || String($0.bindPort).contains(key)
                    || ($0.getMachineName() ?? "").lowercased().contains(key)
            }
        }

        var body: some View {
            PageScaffold(
                search: $searchText,
                searchPrompt: "Search forwards",
                primary: ToolbarAction("New Port Forward", systemImage: "plus", primary: true) {
                    editor = EditorTarget(forward: nil)
                },
                trailingMetrics: .single
            ) {
            } trailing: {
                ToolbarAction("Stop All", systemImage: "stop.circle") {
                    for context in backend.container {
                        backend.endSession(withPortForwardID: context.info.id)
                    }
                }
                .disabled(backend.container.isEmpty)
            } header: {
                PageTitle("Port Forward")
            } content: {
                if store.portForwards.isEmpty {
                    EmptyStateView(
                        "No port forwards",
                        systemImage: "arrow.right",
                        actionTitle: "New Port Forward"
                    ) {
                        editor = EditorTarget(forward: nil)
                    }
                    .rxCard()
                } else if filtered.isEmpty {
                    EmptyStateView("No matches", systemImage: "magnifyingglass")
                        .rxCard()
                } else {
                    table
                }
            }
            .sheet(item: $editor) { target in
                PortForwardEditorSheet(forward: target.forward) { editor = nil }
                    .environmentObject(RayonStore.shared)
            }
            // Edit › Delete… (⌘⌫) deletes the selected row.
            .focusedSceneValue(\.deleteSelection, selection.map { selection in { PortForwardActions.delete(selection) } })
        }

        var table: some View {
            let hasDanger = filtered.contains {
                let running = backend.sessionExists(withPortForwardID: $0.id)
                return PortForwardPresentation(state: backend.lastStatus[$0.id], running: running).status == .danger
            }
            return VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TableHeaderLabel("Orientation").frame(width: ForwardColumns.orientation)
                    TableHeaderLabel("Bind").frame(width: ForwardColumns.bind)
                    TableHeaderLabel("Through").frame(maxWidth: .infinity)
                    TableHeaderLabel("Target").frame(maxWidth: .infinity)
                    if hasDanger {
                        Color.clear.frame(width: ForwardColumns.status, height: 1)
                    }
                    Color.clear.frame(width: ForwardColumns.toggle, height: 1)
                }
                .padding(.horizontal, RX.Space.s3)
                .frame(height: RX.tableHeaderHeight)
                Hairline()
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, forward in
                    PortForwardRow(forward: forward, showStatusColumn: hasDanger, selected: selection == forward.id) {
                        selection = forward.id
                    } edit: {
                        editor = EditorTarget(forward: forward.id)
                    }
                    .rxRise(index)
                    .transition(.opacity)
                }
            }
            .animation(.rxMove, value: filtered.map(\.id))
            .rxCard(padding: RX.Space.s2)
        }
    }

    private struct PortForwardRow: View {
        let forward: RDPortForward
        let showStatusColumn: Bool
        let selected: Bool
        let select: () -> Void
        let edit: () -> Void

        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject var backend = PortForwardBackend.shared
        @State private var hovered = false

        var running: Bool { backend.sessionExists(withPortForwardID: forward.id) }

        var body: some View {
            let status = PortForwardPresentation(state: backend.lastStatus[forward.id], running: running)
            HStack(spacing: 0) {
                RXTag(forward.forwardOrientation.label)
                    .frame(width: ForwardColumns.orientation, alignment: .leading)
                Text(verbatim: ":\(forward.bindPort)")
                    .font(.rxCode)
                    .foregroundStyle(.rxInk)
                    .frame(width: ForwardColumns.bind, alignment: .leading)
                RedactableText(forward.getMachineName() ?? "No server", redacted: redaction == .all)
                    .font(.rxBody)
                    .foregroundStyle(forward.usingMachine == nil ? Color.rxInkSecondary : Color.rxInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: forward.targetLabel)
                    .font(.rxCode)
                    .foregroundStyle(forward.forwardOrientation == .dynamicSOCKS ? Color.rxInkSecondary : Color.rxInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showStatusColumn {
                    Text(status.status == .danger ? status.text : "")
                        .font(.rxBody)
                        .foregroundStyle(.rxDanger)
                        .lineLimit(1)
                        .frame(width: ForwardColumns.status, alignment: .leading)
                }
                Toggle("Running", isOn: Binding(get: { running }, set: { on in
                    if on {
                        backend.createSession(withPortForwardID: forward.id)
                    } else {
                        backend.endSession(withPortForwardID: forward.id)
                    }
                }))
                .labelsHidden()
                .rxSwitchToggle()
                .controlSize(.small)
                .tint(.rxAccent)
                .disabled(!forward.isValid())
                .help(forward.isValid() ? (running ? "Stop" : "Start") : "Incomplete")
                .frame(width: ForwardColumns.toggle, alignment: .trailing)
            }
            .padding(.horizontal, RX.Space.s3)
            .frame(height: RX.tableRowHeight)
            .rxRowBackground(selected: selected, hovered: hovered)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(TapGesture(count: 2).onEnded { if !running { edit() } })
            .simultaneousGesture(TapGesture(count: 1).onEnded(select))
            .contextMenu {
                Button("Edit…", action: edit).disabled(running)
                Button("Duplicate") { PortForwardActions.duplicate(forward.id) }
                Button("Copy SSH Command") { Pasteboard.copy(forward.getCommand() ?? "") }
                    .disabled(forward.getCommand() == nil)
                Divider()
                Button("Delete…", role: .destructive) { PortForwardActions.delete(forward.id) }
            }
        }
    }

    @MainActor
    enum PortForwardActions {
        static func duplicate(_ id: RDPortForward.ID) {
            guard var copy = RayonStore.shared.portForward(id) else { return }
            copy.id = UUID()
            RayonStore.shared.save(copy)
        }

        @MainActor
        static func delete(_ id: RDPortForward.ID) {
            guard let forward = RayonStore.shared.portForward(id) else { return }
            Indicator.confirm(
                message: "Delete the forward on port \(forward.bindPort)?",
                confirmTitle: "Delete"
            ) { confirmed in
                guard confirmed else { return }
                PortForwardBackend.shared.endSession(withPortForwardID: id)
                RayonStore.shared.deletePortForwards([id])
            }
        }
    }

    /// New / Edit Port Forward.
    struct PortForwardEditorSheet: View {
        let forward: RDPortForward.ID?
        let onClose: () -> Void

        @EnvironmentObject var store: RayonStore
        @State private var orientation: RDPortForward.ForwardOrientation = .listenLocal
        @State private var bindPort = ""
        @State private var machine: RDMachine.ID?
        @State private var targetHost = "127.0.0.1"
        @State private var targetPort = ""

        var draft: RDPortForward {
            var result = forward.flatMap { store.portForward($0) } ?? RDPortForward()
            result.forwardOrientation = orientation
            result.bindPort = Int(bindPort) ?? 0
            result.usingMachine = machine
            result.targetHost = targetHost.trimmingCharacters(in: .whitespaces)
            result.targetPort = Int(targetPort) ?? 0
            return result
        }

        var body: some View {
            SheetScaffold(
                forward == nil ? "New Port Forward" : "Edit Port Forward",
                lead: orientation.flowDescription(device: "This Mac")
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    RXField("Orientation") {
                        Picker("Orientation", selection: $orientation) {
                            Text("Local (-L)").tag(RDPortForward.ForwardOrientation.listenLocal)
                            Text("Remote (-R)").tag(RDPortForward.ForwardOrientation.listenRemote)
                            Text("SOCKS5 (-D)").tag(RDPortForward.ForwardOrientation.dynamicSOCKS)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    HStack(alignment: .top, spacing: RX.Space.s4) {
                        RXField("Bind port", error: bindPort.isEmpty || UInt16(bindPort) != nil ? nil : "1–65535") {
                            TextField(orientation == .dynamicSOCKS ? "1080" : "5433", text: $bindPort)
                                .textFieldStyle(.roundedBorder)
                                .font(.rxCode)
                        }
                        .frame(width: 120)
                        RXField("Forward through") {
                            Picker("Forward through", selection: $machine) {
                                Text("Choose a server").tag(RDMachine.ID?.none)
                                ForEach(store.machines) { server in
                                    Text(server.name).tag(RDMachine.ID?.some(server.id))
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    if orientation != .dynamicSOCKS {
                        HStack(alignment: .top, spacing: RX.Space.s4) {
                            RXField("Target host") {
                                TextField("127.0.0.1", text: $targetHost)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.rxCode)
                                    .disableAutocorrection(true)
                            }
                            RXField("Target port", error: targetPort.isEmpty || UInt16(targetPort) != nil ? nil : "1–65535") {
                                TextField("5432", text: $targetPort)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.rxCode)
                            }
                            .frame(width: 120)
                        }
                    } else {
                        HelpText("Runs a local SOCKS5 proxy on 127.0.0.1:\(bindPort.isEmpty ? "1080" : bindPort) that tunnels all connections through the selected server (ssh -D).")
                    }
                    RXField("Equivalent command") {
                        CodeBlock(draft.commandPreview)
                            .opacity(draft.isValid() ? 1 : 0.5)
                    }
                }
            } footer: {
                Button("Cancel", action: onClose)
                    .buttonStyle(.rx)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    store.save(draft)
                    onClose()
                }
                .buttonStyle(.rx)
                .disabled(!draft.isValid())
                Button("Save and Start") {
                    let saved = draft
                    store.save(saved)
                    PortForwardBackend.shared.createSession(withPortForwardID: saved.id)
                    onClose()
                }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid())
            }
            .frame(width: 520)
            .onAppear {
                guard let forward, let read = store.portForward(forward) else { return }
                orientation = read.forwardOrientation
                bindPort = read.bindPort > 0 ? String(read.bindPort) : ""
                machine = read.usingMachine
                targetHost = read.targetHost
                targetPort = read.targetPort > 0 ? String(read.targetPort) : ""
            }
        }
    }

#endif
