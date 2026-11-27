//
//  ServerPicker.swift
//  Rayon
//
//  Servers to act on (Open Terminals, Batch Startup, Run snippet, Deploy
//  Public Key): a Table on the Mac, a List on iPhone and iPad. An offline
//  UU Remote device cannot be picked.
//

import RayonModule
import SwiftUI

struct ServerPicker: View {
    let title: LocalizedStringResource
    var lead: LocalizedStringResource?
    let confirmTitle: LocalizedStringResource
    /// Hears the servers picked, in the store's order; nothing when cancelled.
    let onComplete: @MainActor ([RDMachine.ID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RayonStore.shared
    @ObservedObject private var uuAccount = UURemoteAccount.shared
    @AppSetting(AppSettings.serverRedaction) private var redaction
    @State private var selection = Set<RDMachine.ID>()
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\RDMachine.name, comparator: .localizedStandard)]

    private var machines: [RDMachine] {
        let matching = searchText.isEmpty ? store.machines : store.machines.filter { $0.isQualifiedForSearch(text: searchText) }
        return matching.sorted(using: sortOrder)
    }

    private var picked: [RDMachine.ID] {
        store.machines.filter { selection.contains($0.id) && isReachable($0) }.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
                // The stack gives the sheet a bar for the system's search field.
                NavigationStack {
                    table.searchable(text: $searchText, placement: .toolbar, prompt: Text("Search servers"))
                }
            #else
                list
            #endif
            HStack {
                if let lead {
                    Text(lead)
                        .font(.footnote)
                        .foregroundStyle(.rxInkSecondary)
                }
                Spacer()
                Text("\(picked.count) selected")
                    .monospacedDigit()
                    .foregroundStyle(.rxInkSecondary)
                Button(allSelected ? "Deselect All" : "Select All") {
                    let ids = machines.filter(isReachable).map(\.id)
                    if allSelected { selection.subtract(ids) } else { selection.formUnion(ids) }
                }
                .disabled(!machines.contains(where: isReachable))
            }
            .padding(RX.Space.s4)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) {
                    let result = picked
                    dismiss()
                    onComplete(result)
                }
                .disabled(picked.isEmpty)
            }
        }
        .editorSheet(title)
    }

    private var allSelected: Bool {
        let reachable = machines.filter(isReachable)
        return !reachable.isEmpty && reachable.allSatisfy { selection.contains($0.id) }
    }

    /// An offline UU Remote device can't be reached for anything picked here.
    private func isReachable(_ machine: RDMachine) -> Bool {
        uuOnline(machine) != false
    }

    /// Whether a UU Remote device is online; nil for any other server.
    private func uuOnline(_ machine: RDMachine) -> Bool? {
        guard machine.isUURemoteDevice else { return nil }
        return uuAccount.devices.first { $0.deviceID == machine.uuDeviceID }?.isOnline ?? false
    }

    @ViewBuilder private func address(_ machine: RDMachine) -> some View {
        if let online = uuOnline(machine) {
            Text(online ? "UU Remote · Online" : "UU Remote · Offline")
                .foregroundStyle(.rxInkSecondary)
        } else {
            RedactableText(machine.displayAddress, redacted: redaction != .none)
                .font(.rxCode)
                .foregroundStyle(.rxInkSecondary)
        }
    }

    #if os(macOS)
        private var table: some View {
            Table(machines, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name, comparator: .localizedStandard) { machine in
                    RedactableText(machine.name, redacted: redaction == .all)
                        .opacity(isReachable(machine) ? 1 : 0.5)
                }
                TableColumn("Address", value: \.remoteAddress, comparator: .localizedStandard) { machine in
                    address(machine)
                }
                TableColumn("Folder") { machine in
                    Text(store.folder(machine.folderId)?.name ?? String(localized: "Default"))
                        .foregroundStyle(.rxInkSecondary)
                }
            }
            .overlay {
                if machines.isEmpty {
                    ContentUnavailableView(store.machines.isEmpty ? "No servers yet" : "No matches", systemImage: "server.rack")
                }
            }
            .frame(minHeight: 300)
        }
    #else
        private var list: some View {
            List(machines, selection: $selection) { machine in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        RedactableText(machine.name, redacted: redaction == .all)
                            .foregroundStyle(.rxInk)
                        address(machine)
                            .font(.caption)
                    }
                    Spacer()
                    if let folder = store.folder(machine.folderId) {
                        RXTag("\(folder.name)")
                    }
                }
                .opacity(isReachable(machine) ? 1 : 0.5)
            }
            .environment(\.editMode, .constant(.active))
            .searchable(text: $searchText, prompt: "Search servers")
            .overlay {
                if machines.isEmpty {
                    ContentUnavailableView(store.machines.isEmpty ? "No servers yet" : "No matches", systemImage: "server.rack")
                }
            }
        }
    #endif
}

extension ServerPicker {
    /// Asks for servers over the window in front; `onComplete` hears a
    /// selection, not a cancel.
    @MainActor
    static func present(
        title: LocalizedStringResource,
        lead: LocalizedStringResource? = nil,
        confirmTitle: LocalizedStringResource,
        onComplete: @escaping @MainActor ([RDMachine.ID]) -> Void
    ) {
        let picker = ServerPicker(title: title, lead: lead, confirmTitle: confirmTitle) { picked in
            if !picked.isEmpty { onComplete(picked) }
        }
        #if os(macOS)
            AppRouter.shared.present { _ in picker }
        #else
            RayonUtil.presentModalSheet(rootView: picker)
        #endif
    }
}
