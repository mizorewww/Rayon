//
//  PortForwardView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/10.
//

import RayonModule
import SwiftUI

struct PortForwardView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var backend = PortForwardBackend.shared
    @State private var openCreate = false

    var body: some View {
        Group {
            if store.portForwardGroup.forwards.isEmpty {
                EmptyStateView(
                    "No port forwards",
                    systemImage: "arrow.right",
                    message: "Reach a port on a server, or expose a local port to it, through the server's SSH connection.",
                    actionTitle: "New Port Forward"
                ) {
                    openCreate = true
                }
                .frame(maxHeight: .infinity)
                .background(RXBackdrop().ignoresSafeArea())
            } else {
                List {
                    Section {
                        ForEach(store.portForwardGroup.forwards) { forward in
                            PortForwardRow(forward: forward)
                                .rxListRow()
                        }
                    } header: {
                        RXSectionHeader("\(backend.container.count) running")
                    } footer: {
                        Text("Traffic goes through each server's SSH connection.")
                    }
                }
                .rxGroupedList()
            }
        }
        .navigationTitle("Port Forward")
        .toolbar {
            ToolbarItem {
                Button {
                    openCreate = true
                } label: {
                    Label("New Port Forward", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $openCreate) {
            NavigationStack { EditPortForwardView() }
        }
    }
}

private struct PortForwardRow: View {
    let forward: RDPortForward
    @EnvironmentObject var store: RayonStore
    @ObservedObject var backend = PortForwardBackend.shared
    @State private var openEdit = false

    var running: Bool { backend.sessionExists(withPortForwardID: forward.id) }

    var status: (RXStatus, String) {
        switch backend.lastHint[forward.id] {
        case "awaiting connect", "opening channel": return (.running, "Connecting")
        case "forward running": return running ? (.success, "Running") : (.off, "Stopped")
        case "failed connect": return (.danger, "Could not connect")
        case "failed authenticate": return (.danger, "Could not sign in")
        case "forward stopped": return running ? (.danger, "Forward ended") : (.off, "Stopped")
        default: return running ? (.running, "Starting") : (.off, "Stopped")
        }
    }

    var body: some View {
        HStack(spacing: RX.Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RXTag(forward.forwardOrientation == .listenLocal ? "Listen local" : "Listen remote")
                    Text(":\(forward.bindPort)")
                        .font(.rxCode)
                        .foregroundStyle(.rxInk)
                }
                Text("\(forward.getMachineName() ?? "No server") → \(forward.targetHost):\(forward.targetPort)")
                    .font(.rxCode)
                    .foregroundStyle(.rxInkSecondary)
                    .lineLimit(1)
                if status.0 == .danger {
                    Text(status.1)
                        .font(.caption)
                        .foregroundStyle(.rxDanger)
                }
            }
            Spacer()
            Toggle("Running", isOn: Binding(get: { running }, set: { on in
                if on {
                    backend.createSession(withPortForwardID: forward.id)
                } else {
                    backend.endSession(withPortForwardID: forward.id)
                }
            }))
            .labelsHidden()
            .tint(.rxAccent)
            .disabled(!forward.isValid())
        }
        .contentShape(Rectangle())
        .onTapGesture { if !running { openEdit = true } }
        .swipeActions {
            Button(role: .destructive) {
                UIBridge.requiresConfirmation(message: "Delete the forward on port \(forward.bindPort)?") { confirmed in
                    guard confirmed else { return }
                    backend.endSession(withPortForwardID: forward.id)
                    store.portForwardGroup.delete(forward.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                UIBridge.sendPasteboard(str: forward.getCommand() ?? "")
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }
            Button {
                var copy = forward
                copy.id = .init()
                store.portForwardGroup.insert(copy)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        .sheet(isPresented: $openEdit) {
            NavigationStack { EditPortForwardView { forward.id } }
        }
    }
}
