//
//  PickerSheets+macOS.swift
//  Rayon
//
//  The picker of a UU Remote device's detached terminal sessions, and the
//  terminal or server a split joins.
//

#if os(macOS)
    import RayonDesign
    import RayonModule
    import SwiftUI

    /// A UU Remote device keeps its terminal sessions after their tab is gone
    /// (closed, Rayon quit, or the connection dropped): one of them, or a new
    /// one. Ending a session is done here and nowhere else.
    struct UURemoteSessionPickerSheet: View {
        typealias Choice = UURemoteSessionChoice

        let machine: RDMachine
        /// nil when cancelled.
        let onComplete: (Choice?) -> Void

        @StateObject private var list: UURemoteSessionList
        @State private var ending: UUTerminalSession?

        init(machine: RDMachine, onComplete: @escaping (Choice?) -> Void) {
            self.machine = machine
            self.onComplete = onComplete
            _list = StateObject(wrappedValue: UURemoteSessionList(machine: machine))
        }

        var body: some View {
            SheetScaffold(
                "Terminal on \(machine.name)",
                lead: "A session keeps running on the device after its tab closes, until you end it here. Resume one, or start a new one."
            ) {
                content
                    .frame(height: 240)
                    .background(
                        RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                            .fill(Color.rxSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                                    .strokeBorder(Color.rxHairline, lineWidth: 1)
                            )
                    )
            } footer: {
                Button("End Session…") {
                    ending = list.sessions.first { $0.id == list.selection }
                }
                .buttonStyle(.rxDanger)
                .disabled(list.selection == nil)
                Spacer()
                Button("Cancel") { onComplete(nil) }
                    .buttonStyle(.rx)
                    .keyboardShortcut(.cancelAction)
                Button("New Session") { onComplete(.new) }
                    .buttonStyle(.rx)
                Button("Resume") {
                    if let selection = list.selection { onComplete(.resume(selection)) }
                }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(list.selection == nil)
            }
            .frame(width: 520)
            .task { await load() }
            .alert(
                "End \(ending?.name ?? "the session")?",
                isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
                presenting: ending
            ) { session in
                Button("End Session", role: .destructive) { Task { await end(session) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its shell, and whatever runs in it, stops on \(machine.name).")
            }
        }

        @ViewBuilder private var content: some View {
            switch list.phase {
            case .loading:
                VStack(spacing: RX.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(list.status.isEmpty ? "Connecting to \(machine.name)…" : "\(list.status)")
                        .font(.rxCaption)
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                EmptyStateView(
                    "Sessions could not be listed",
                    systemImage: "exclamationmark.triangle",
                    message: "\(reason)",
                    actionTitle: "Try Again"
                ) {
                    Task { await load() }
                }
            case .loaded:
                ScrollView {
                    RXDividedStack {
                        ForEach(list.sessions) { session in
                            row(session)
                        }
                    }
                    .padding(RX.Space.s2)
                }
            }
        }

        private func row(_ session: UUTerminalSession) -> some View {
            let isSelected = list.selection == session.id
            return Button {
                list.selection = session.id
            } label: {
                HStack(spacing: RX.Space.s3) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? Color.rxAccent : Color.rxControlBorder)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.name)
                            .font(.rxBody)
                            .foregroundStyle(.rxInk)
                        Text("Last used \(UURemoteSessionList.relative(session.lastActive)) · started \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.rxCaption)
                            .foregroundStyle(.rxInkSecondary)
                    }
                    Spacer()
                    if !session.isDetached {
                        RXTag("Attached")
                    }
                    if !session.shell.isEmpty { RXTag("\(session.shell)") }
                }
                .padding(.horizontal, RX.Space.s2)
                .frame(height: RX.tableRowHeight)
                .rxRowBackground(selected: isSelected)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { onComplete(.resume(session.id)) })
        }

        private func load() async {
            if await !list.load() { onComplete(.new) }
        }

        private func end(_ session: UUTerminalSession) async {
            if await !list.end(session) { onComplete(.new) }
        }
    }

    /// What joins the split in front, from "Split with Server…": a terminal
    /// already open, on any server, or a new one to a saved server or the
    /// local shell.
    struct SplitWithServerSheet: View {
        enum Choice: Hashable {
            case tab(TerminalManager.Context.ID)
            case server(RDMachine.ID)
            case local
        }

        let current: TerminalManager.Context
        /// nil when cancelled.
        let onComplete: (Choice?) -> Void

        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject private var terminals = TerminalManager.shared
        @ObservedObject private var uuAccount = UURemoteAccount.shared
        @State private var selection: Choice?
        @State private var searchText = ""

        private var openTabs: [TerminalManager.Context] {
            let all = terminals.splitCandidates(for: current)
            guard !searchText.isEmpty else { return all }
            let key = searchText.lowercased()
            return all.filter {
                $0.displayName.lowercased().contains(key) || $0.navigationSubtitle.lowercased().contains(key)
            }
        }

        private var machines: [RDMachine] {
            let all = store.machines.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !searchText.isEmpty else { return all }
            return all.filter { $0.isQualifiedForSearch(text: searchText) }
        }

        private var showsLocal: Bool {
            searchText.isEmpty || "local terminal".contains(searchText.lowercased())
        }

        // The stack gives the sheet a bar for the system's search field.
        var body: some View {
            NavigationStack {
                sheet.searchable(text: $searchText, placement: .toolbar, prompt: Text("Search terminals and servers"))
            }
        }

        private var sheet: some View {
            SheetScaffold(
                "Split with Server",
                lead: "Show another terminal beside this one, from any server. Three panes or more are laid out as a grid."
            ) {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: RX.Space.s3) {
                            if !openTabs.isEmpty {
                                RXSectionHeader(LocalizedStringResource("Open Terminals (section)", defaultValue: "Open Terminals", comment: "Header over the terminal tabs already open"))
                                    .padding(.horizontal, RX.Space.s2)
                                RXDividedStack {
                                    ForEach(openTabs) { tab in
                                        row(
                                            .tab(tab.id),
                                            title: tab.displayName,
                                            detail: tab.navigationSubtitle,
                                            redactTitle: tab.remoteType == .machine && redaction == .all,
                                            systemImage: tab.closed ? "bolt.slash" : "terminal"
                                        )
                                    }
                                }
                            }
                            RXSectionHeader("New Terminal")
                                .padding(.horizontal, RX.Space.s2)
                            RXDividedStack {
                                ForEach(machines) { machine in
                                    serverRow(machine)
                                }
                                if showsLocal {
                                    row(.local, title: "Local Terminal", detail: ProcessInfo.processInfo.hostName, systemImage: "laptopcomputer")
                                }
                            }
                        }
                        .padding(RX.Space.s2)
                    }
                    .frame(height: 340)
                    .background(
                        RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                            .fill(Color.rxSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                                    .strokeBorder(Color.rxHairline, lineWidth: 1)
                            )
                    )
                }
            } footer: {
                Spacer()
                Button("Cancel") { onComplete(nil) }
                    .buttonStyle(.rx)
                    .keyboardShortcut(.cancelAction)
                Button("Split") { onComplete(selection) }
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .frame(width: 520)
        }

        private func serverRow(_ machine: RDMachine) -> some View {
            let online: Bool? = machine.isUURemoteDevice
                ? uuAccount.devices.first { $0.deviceID == machine.uuDeviceID }?.isOnline ?? false
                : nil
            let detail = online.map { $0 ? String(localized: "UU Remote · Online") : String(localized: "UU Remote · Offline") }
                ?? "\(machine.remoteAddress):\(machine.remotePort)"
            return row(
                .server(machine.id),
                title: machine.name,
                detail: detail,
                redactTitle: redaction == .all,
                redactDetail: online == nil && redaction != .none,
                systemImage: "server.rack"
            )
            .disabled(online == false)
            .opacity(online == false ? 0.5 : 1)
        }

        private func row(
            _ choice: Choice,
            title: String,
            detail: String,
            redactTitle: Bool = false,
            redactDetail: Bool = false,
            systemImage: String
        ) -> some View {
            let isSelected = selection == choice
            return Button {
                selection = choice
            } label: {
                HStack(spacing: RX.Space.s3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .foregroundStyle(isSelected ? Color.rxAccent : Color.rxInkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        RedactableText(title, redacted: redactTitle)
                            .font(.rxBody)
                            .foregroundStyle(.rxInk)
                        if !detail.isEmpty {
                            RedactableText(detail, redacted: redactDetail)
                                .font(.rxCaption)
                                .foregroundStyle(.rxInkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, RX.Space.s2)
                .frame(height: RX.tableRowHeight)
                .rxRowBackground(selected: isSelected)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { onComplete(choice) })
        }
    }

#endif
