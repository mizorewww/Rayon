//
//  PortForwardView.swift
//  Rayon (macOS)
//
//  Forwards: orientation, bind, through server, target, status and an on/off switch.
//

import RayonModule
import SwiftUI

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
        let all = store.portForwardGroup.forwards
        guard !searchText.isEmpty else { return all }
        let key = searchText.lowercased()
        return all.filter {
            $0.targetHost.lowercased().contains(key)
                || String($0.targetPort).contains(key)
                || String($0.bindPort).contains(key)
                || ($0.getMachineName() ?? "").lowercased().contains(key)
        }
    }

    var subtitle: String {
        let running = backend.container.count
        return "\(running) running · traffic goes through each server's SSH connection"
    }

    var body: some View {
        PageScaffold(search: $searchText, searchPrompt: "Search forwards") {
        } trailing: {
            ToolbarAction("Stop All", systemImage: "stop.circle") {
                for context in backend.container {
                    backend.endSession(withPortForwardID: context.info.id)
                }
            }
            .disabled(backend.container.isEmpty)
            ToolbarAction("New Port Forward", systemImage: "plus", primary: true) {
                editor = EditorTarget(forward: nil)
            }
        } header: {
            PageTitle("Port Forward", subtitle: subtitle)
        } content: {
            if store.portForwardGroup.forwards.isEmpty {
                EmptyStateView(
                    "No port forwards",
                    systemImage: "arrow.right",
                    message: "Reach a port on a server, or expose a local port to it, through the server's SSH connection.",
                    actionTitle: "New Port Forward"
                ) {
                    editor = EditorTarget(forward: nil)
                }
                .rxCard()
            } else if filtered.isEmpty {
                EmptyStateView("No matches", systemImage: "magnifyingglass", message: "No forward matches “\(searchText)”.")
                    .rxCard()
            } else {
                table
            }
        }
        .sheet(item: $editor) { target in
            PortForwardEditorSheet(forward: target.forward) { editor = nil }
        }
        .background {
            // ⌘⌫ deletes the selected row.
            Button("Delete") {
                if let selection { PortForwardActions.delete(selection) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selection == nil)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TableHeaderLabel("Orientation").frame(width: 120)
                TableHeaderLabel("Bind").frame(width: 90)
                TableHeaderLabel("Through").frame(maxWidth: .infinity)
                TableHeaderLabel("Target").frame(maxWidth: .infinity)
                Color.clear.frame(width: 200, height: 1)
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.horizontal, RX.Space.s3)
            .frame(height: RX.tableHeaderHeight)
            Hairline()
            ForEach(filtered) { forward in
                PortForwardRow(forward: forward, selected: selection == forward.id) {
                    selection = forward.id
                } edit: {
                    editor = EditorTarget(forward: forward.id)
                }
            }
        }
        .rxCard(padding: RX.Space.s2)
    }
}

private struct PortForwardRow: View {
    let forward: RDPortForward
    let selected: Bool
    let select: () -> Void
    let edit: () -> Void

    @EnvironmentObject var store: RayonStore
    @ObservedObject var backend = PortForwardBackend.shared
    @State private var hovered = false

    var running: Bool { backend.sessionExists(withPortForwardID: forward.id) }

    var body: some View {
        let status = PortForwardStatus(hint: backend.lastHint[forward.id], running: running)
        HStack(spacing: 0) {
            RXTag(forward.forwardOrientation == .listenLocal ? "Listen local" : "Listen remote")
                .frame(width: 120, alignment: .leading)
            Text(":\(forward.bindPort)")
                .font(.rxCode)
                .foregroundStyle(.rxInk)
                .frame(width: 90, alignment: .leading)
            RedactableText(forward.getMachineName() ?? "No server", redacted: store.machineRedacted == .all)
                .font(.rxBody)
                .foregroundStyle(forward.usingMachine == nil ? Color.rxInkSecondary : Color.rxInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(forward.targetHost.isEmpty ? "—" : "\(forward.targetHost):\(forward.targetPort)")
                .font(.rxCode)
                .foregroundStyle(.rxInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(status.status == .danger ? status.text : "")
                .font(.rxBody)
                .foregroundStyle(.rxDanger)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
            Toggle("Running", isOn: Binding(get: { running }, set: { on in
                if on {
                    backend.createSession(withPortForwardID: forward.id)
                } else {
                    backend.endSession(withPortForwardID: forward.id)
                }
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.rxAccent)
            .disabled(!forward.isValid())
            .help(forward.isValid() ? (running ? "Stop" : "Start") : "Complete the forward before starting it")
            .frame(width: 52, alignment: .trailing)
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
            Button("Copy SSH Command") { UIBridge.sendPasteboard(str: forward.getCommand() ?? "") }
                .disabled(forward.getCommand() == nil)
            Divider()
            Button("Delete…", role: .destructive) { PortForwardActions.delete(forward.id) }
        }
    }
}

/// Maps the backend's progress hints to a dot and a word.
struct PortForwardStatus {
    let status: RXStatus
    let text: String

    init(hint: String?, running: Bool) {
        switch hint {
        case "awaiting connect", "opening channel":
            (status, text) = (.running, "Connecting")
        case "forward running":
            (status, text) = running ? (.success, "Running") : (.off, "Stopped")
        case "failed connect":
            (status, text) = (.danger, "Could not connect")
        case "failed authenticate":
            (status, text) = (.danger, "Could not sign in")
        case "forward stopped":
            (status, text) = running ? (.danger, "Forward ended") : (.off, "Stopped")
        default:
            (status, text) = running ? (.running, "Starting") : (.off, "Stopped")
        }
    }
}

enum PortForwardActions {
    static func duplicate(_ id: RDPortForward.ID) {
        var copy = RayonStore.shared.portForwardGroup[id]
        copy.id = UUID()
        RayonStore.shared.portForwardGroup.insert(copy)
    }

    static func delete(_ id: RDPortForward.ID) {
        let forward = RayonStore.shared.portForwardGroup[id]
        UIBridge.requiresConfirmation(
            message: "Delete the forward on port \(forward.bindPort)?",
            informative: "It stops if it is running.",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            PortForwardBackend.shared.endSession(withPortForwardID: id)
            RayonStore.shared.portForwardGroup.delete(id)
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
        var result = forward.map { store.portForwardGroup[$0] } ?? RDPortForward()
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
            lead: orientation == .listenLocal
                ? "Connections to the bind port on this Mac go through the server to the target."
                : "Connections to the bind port on the server come back through this Mac to the target."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                RXField("Orientation") {
                    RXSegmented(selection: $orientation, options: [
                        .init(.listenLocal, "Listen local"),
                        .init(.listenRemote, "Listen remote"),
                    ], caps: false, fullWidth: true)
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Bind port", error: bindPort.isEmpty || UInt16(bindPort) != nil ? nil : "1–65535") {
                        TextField("5433", text: $bindPort)
                            .textFieldStyle(.rxMono)
                    }
                    .frame(width: 120)
                    RXField("Forward through") {
                        RXPicker(
                            selection: $machine,
                            options: store.machineGroup.machines.map { .init(RDMachine.ID?.some($0.id), $0.name) },
                            placeholder: "Choose a server"
                        )
                    }
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Target host") {
                        TextField("127.0.0.1", text: $targetHost)
                            .textFieldStyle(.rxMono)
                            .disableAutocorrection(true)
                    }
                    RXField("Target port", error: targetPort.isEmpty || UInt16(targetPort) != nil ? nil : "1–65535") {
                        TextField("5432", text: $targetPort)
                            .textFieldStyle(.rxMono)
                    }
                    .frame(width: 120)
                }
                if let command = draft.getCommand(), draft.isValid() {
                    RXField("Equivalent command") {
                        CodeBlock(command)
                    }
                }
            }
        } footer: {
            Spacer()
            Button("Cancel", action: onClose)
                .buttonStyle(.rx)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                store.portForwardGroup.insert(draft)
                onClose()
            }
            .buttonStyle(.rx)
            .disabled(!draft.isValid())
            Button("Save and Start") {
                let saved = draft
                store.portForwardGroup.insert(saved)
                PortForwardBackend.shared.createSession(withPortForwardID: saved.id)
                onClose()
            }
            .buttonStyle(.rxPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.isValid())
        }
        .frame(width: 520)
        .onAppear {
            guard let forward else { return }
            let read = store.portForwardGroup[forward]
            orientation = read.forwardOrientation
            bindPort = read.bindPort > 0 ? String(read.bindPort) : ""
            machine = read.usingMachine
            targetHost = read.targetHost
            targetPort = read.targetPort > 0 ? String(read.targetPort) : ""
        }
    }
}
