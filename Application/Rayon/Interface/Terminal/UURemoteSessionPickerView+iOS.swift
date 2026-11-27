//
//  UURemoteSessionPickerView+iOS.swift
//  Rayon
//
//  A UU Remote device keeps its terminal sessions after their tab is gone
//  (closed, Rayon quit, or the connection dropped): one of them, or a new
//  one. Ending a session is done here and nowhere else.
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    struct UURemoteSessionPickerView: View {
        typealias Choice = UURemoteSessionChoice

        let machine: RDMachine
        /// nil when cancelled.
        let onComplete: (Choice?) -> Void

        @Environment(\.dismiss) private var dismiss

        @StateObject private var list: UURemoteSessionList
        @State private var ending: UUTerminalSession?

        init(machine: RDMachine, onComplete: @escaping (Choice?) -> Void) {
            self.machine = machine
            self.onComplete = onComplete
            _list = StateObject(wrappedValue: UURemoteSessionList(machine: machine))
        }

        /// Presents the picker over the app; `onComplete` hears the choice once.
        @MainActor
        static func present(machine: RDMachine, onComplete: @escaping (Choice?) -> Void) {
            let picker = NavigationStack {
                UURemoteSessionPickerView(machine: machine, onComplete: onComplete)
            }
            .tint(.rxAccent)
            RayonUtil.presentModalSheet(rootView: picker)
        }

        var body: some View {
            content
                .background(RXBackdrop().ignoresSafeArea())
                .navigationTitle("Terminal on \(machine.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { finish(nil) }
                            .keyboardShortcut(.cancelAction)
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button("New Session") { finish(.new) }
                            .keyboardShortcut("n", modifiers: .command)
                        Button {
                            if let selection = list.selection { finish(.resume(selection)) }
                        } label: {
                            Text("Resume").bold()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(list.selection == nil)
                    }
                }
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
                    ProgressView()
                    Text(list.status.isEmpty ? "Connecting to \(machine.name)…" : list.status)
                        .font(.footnote)
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                EmptyStateView(
                    "Sessions could not be listed",
                    systemImage: "exclamationmark.triangle",
                    message: reason,
                    actionTitle: "Try Again"
                ) {
                    Task { await load() }
                }
                .frame(maxHeight: .infinity)
            case .loaded:
                List {
                    Section {
                        ForEach(list.sessions) { session in
                            row(session)
                                .rxListRow()
                                .swipeActions {
                                    Button("End Session", role: .destructive) { ending = session }
                                }
                                .contextMenu {
                                    Button { finish(.resume(session.id)) } label: {
                                        Label("Resume", systemImage: "play")
                                    }
                                    Button(role: .destructive) { ending = session } label: {
                                        Label("End Session…", systemImage: "xmark.octagon")
                                    }
                                }
                        }
                    } footer: {
                        Text("A session keeps running on the device after its tab closes, until you end it here. Resume one, or start a new one.")
                    }
                }
                .rxGroupedList()
            }
        }

        private func row(_ session: UUTerminalSession) -> some View {
            let isSelected = list.selection == session.id
            return Button {
                list.selection = session.id
            } label: {
                HStack(spacing: RX.Space.s3) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isSelected ? Color.rxAccent : Color.rxInkTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .foregroundStyle(.rxInk)
                        Text("Last used \(UURemoteSessionList.relative(session.lastActive)) · started \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.rxInkSecondary)
                    }
                    Spacer()
                    if !session.isDetached {
                        RXTag("Attached")
                    }
                    if !session.shell.isEmpty { RXTag(session.shell) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private func finish(_ choice: Choice?) {
            dismiss()
            onComplete(choice)
        }

        private func load() async {
            if await !list.load() { finish(.new) }
        }

        private func end(_ session: UUTerminalSession) async {
            if await !list.end(session) { finish(.new) }
        }
    }

#endif
