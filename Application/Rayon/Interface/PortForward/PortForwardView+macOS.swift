//
//  PortForwardView+macOS.swift
//  Rayon
//
//  Forwards in a native Table: orientation, bind, through server, target,
//  status and an on/off switch. The first four sort; several forwards can be
//  chosen to start, stop or delete together.
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    struct PortForwardView: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject var backend = PortForwardBackend.shared

        @State private var searchText = ""
        @State private var selection = Set<RDPortForward.ID>()
        /// Empty keeps the order the forwards were made in.
        @State private var sortOrder: [KeyPathComparator<RDPortForward>] = []
        @State private var editor: EditorTarget?

        struct EditorTarget: Identifiable {
            let id = UUID()
            let forward: RDPortForward.ID?
        }

        var filtered: [RDPortForward] {
            let all = store.portForwards.sorted(using: sortOrder)
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
                scrolls: false,
                search: $searchText,
                searchPrompt: "Search forwards",
                primary: ToolbarAction("New Port Forward", systemImage: "plus", primary: true) {
                    editor = EditorTarget(forward: nil)
                }
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
            // Edit › Delete… (⌘⌫) deletes the chosen forwards.
            .focusedSceneValue(\.deleteSelection, selection.isEmpty ? nil : { [selection] in PortForwardActions.delete(Array(selection)) })
        }

        var table: some View {
            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Orientation", value: \.forwardOrientation.label, comparator: .localizedStandard) { forward in
                    RXTag("\(forward.forwardOrientation.label)")
                }
                .width(min: 90, ideal: 115)
                TableColumn("Bind", value: \.bindPort) { forward in
                    Text(verbatim: ":\(forward.bindPort)")
                        .font(.rxCode)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Through", value: \.machineName, comparator: .localizedStandard) { forward in
                    RedactableText(forward.getMachineName() ?? String(localized: "No server"), redacted: redaction == .all)
                        .foregroundStyle(forward.usingMachine == nil ? Color.rxInkSecondary : Color.rxInk)
                        .lineLimit(1)
                }
                TableColumn("Target", value: \.targetLabel, comparator: .localizedStandard) { forward in
                    Text(verbatim: forward.targetLabel)
                        .font(.rxCode)
                        .foregroundStyle(forward.forwardOrientation == .dynamicSOCKS ? Color.rxInkSecondary : Color.rxInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("Status") { forward in
                    let status = presentation(forward)
                    Label {
                        Text(status.text)
                            .foregroundStyle(status.status == .danger ? Color.rxDanger : Color.rxInkSecondary)
                    } icon: {
                        StatusDot(status.status, size: .small)
                    }
                }
                .width(min: 90, ideal: 120)
                TableColumn("Running") { forward in
                    runningToggle(forward)
                }
                .width(52)
            }
            .contextMenu(forSelectionType: RDPortForward.ID.self) { chosen in
                let forwards = filtered.filter { chosen.contains($0.id) }
                if forwards.count == 1 { menu(for: forwards[0]) } else if !forwards.isEmpty { menu(for: forwards) }
            } primaryAction: { chosen in
                if chosen.count == 1, let id = chosen.first, !backend.sessionExists(withPortForwardID: id) {
                    editor = EditorTarget(forward: id)
                }
            }
        }

        func presentation(_ forward: RDPortForward) -> PortForwardPresentation {
            PortForwardPresentation(state: backend.lastStatus[forward.id], running: backend.sessionExists(withPortForwardID: forward.id))
        }

        func runningToggle(_ forward: RDPortForward) -> some View {
            let running = backend.sessionExists(withPortForwardID: forward.id)
            return Toggle("Running", isOn: Binding(get: { running }, set: { on in
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
        }

        /// Start and Stop for several forwards, each where it applies.
        @ViewBuilder func menu(for forwards: [RDPortForward]) -> some View {
            let stopped = forwards.filter { $0.isValid() && !backend.sessionExists(withPortForwardID: $0.id) }
            let running = forwards.filter { backend.sessionExists(withPortForwardID: $0.id) }
            Button("Start") {
                for forward in stopped { backend.createSession(withPortForwardID: forward.id) }
            }
            .disabled(stopped.isEmpty)
            Button("Stop") {
                for forward in running { backend.endSession(withPortForwardID: forward.id) }
            }
            .disabled(running.isEmpty)
            Divider()
            Button("Delete…", role: .destructive) { PortForwardActions.delete(forwards.map(\.id)) }
        }

        @ViewBuilder func menu(for forward: RDPortForward) -> some View {
            Button("Edit…") { editor = EditorTarget(forward: forward.id) }
                .disabled(backend.sessionExists(withPortForwardID: forward.id))
            Button("Duplicate") { PortForwardActions.duplicate(forward.id) }
            Button("Copy SSH Command") { Pasteboard.copy(forward.getCommand() ?? "") }
                .disabled(forward.getCommand() == nil)
            Divider()
            Button("Delete…", role: .destructive) { PortForwardActions.delete([forward.id]) }
        }
    }

    private extension RDPortForward {
        /// The server's name, for sorting by the Through column.
        var machineName: String { getMachineName() ?? "" }
    }

    @MainActor
    enum PortForwardActions {
        static func duplicate(_ id: RDPortForward.ID) {
            guard var copy = RayonStore.shared.portForward(id) else { return }
            copy.id = UUID()
            RayonStore.shared.save(copy)
        }

        static func delete(_ ids: [RDPortForward.ID]) {
            let forwards = ids.compactMap { RayonStore.shared.portForward($0) }
            guard let first = forwards.first else { return }
            Indicator.confirm(
                message: forwards.count == 1 ? "Delete the forward on port \(first.bindPort)?" : "Delete \(forwards.count) forwards?",
                confirmTitle: "Delete",
                destructive: true
            ) { confirmed in
                guard confirmed else { return }
                for forward in forwards { PortForwardBackend.shared.endSession(withPortForwardID: forward.id) }
                RayonStore.shared.deletePortForwards(forwards.map(\.id))
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
                lead: "\(orientation.flowDescription(device: String(localized: "This Mac")))"
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
                                // A server deleted since: a tagged row, or the Picker draws blank.
                                if let missing = machine, store.machine(missing) == nil {
                                    Text("Choose a server").tag(RDMachine.ID?.some(missing))
                                }
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
