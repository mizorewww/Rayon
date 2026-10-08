//
//  IdentityView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI

struct IdentityView: View {
    @EnvironmentObject var store: RayonStore
    @State private var searchKey = ""
    @State private var openCreate = false

    var filtered: [RDIdentity] {
        let all = store.identityGroup.identities
        guard !searchKey.isEmpty else { return all }
        let key = searchKey.lowercased()
        return all.filter {
            $0.username.lowercased().contains(key)
                || $0.comment.lowercased().contains(key)
                || $0.group.lowercased().contains(key)
        }
    }

    var groups: [(name: String, identities: [RDIdentity])] {
        let names = Set(filtered.map(\.group)).sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return names.map { name in (name, filtered.filter { $0.group == name }.sorted { $0.username < $1.username }) }
    }

    var body: some View {
        Group {
            if store.identityGroup.identities.isEmpty {
                EmptyStateView(
                    "No identities yet",
                    systemImage: "person",
                    message: "An identity is a username with a password or key pair. Servers and Quick Connect sign in with it.",
                    actionTitle: "New Identity"
                ) {
                    openCreate = true
                }
                .frame(maxHeight: .infinity)
                .background(RXBackdrop().ignoresSafeArea())
            } else {
                List {
                    ForEach(groups, id: \.name) { group in
                        Section {
                            ForEach(group.identities) { identity in
                                NavigationLink {
                                    EditIdentityView { identity.id }
                                } label: {
                                    IdentityRow(identity: identity)
                                }
                                .rxListRow()
                                .swipeActions {
                                    Button(role: .destructive) {
                                        UIBridge.requiresConfirmation(message: "Delete identity \(identity.username)?") { confirmed in
                                            if confirmed { store.identityGroup.delete(identity.id) }
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    if !identity.publicKey.isEmpty {
                                        Button {
                                            UIBridge.sendPasteboard(str: identity.publicKey)
                                        } label: {
                                            Label("Copy Public Key", systemImage: "doc.on.doc")
                                        }
                                    }
                                    Button {
                                        var copy = identity
                                        copy.id = UUID()
                                        store.identityGroup.insert(copy)
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                }
                            }
                        } header: {
                            RXSectionHeader(group.name.isEmpty ? "Default" : group.name)
                        }
                    }
                }
                .rxGroupedList()
                .searchable(text: $searchKey, prompt: "Search identities")
            }
        }
        .navigationTitle("Identities")
        .toolbar {
            ToolbarItem {
                Button {
                    openCreate = true
                } label: {
                    Label("New Identity", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $openCreate) {
            NavigationStack { EditIdentityView() }
        }
    }
}

private struct IdentityRow: View {
    let identity: RDIdentity
    @EnvironmentObject var store: RayonStore

    var usage: Int {
        store.machineGroup.machines.filter { $0.associatedIdentity == identity.id.uuidString }.count
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.username)
                    .foregroundStyle(.rxInk)
                Text(identity.authDescription + (identity.authenticAutomatically ? " · Automatic" : ""))
                    .font(.caption)
                    .foregroundStyle(.rxInkSecondary)
            }
            Spacer()
            Text("\(usage) server\(usage == 1 ? "" : "s")")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.rxInkSecondary)
        }
    }
}
