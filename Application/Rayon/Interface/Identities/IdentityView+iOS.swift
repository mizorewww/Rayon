//
//  IdentityView+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/2.
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    struct IdentityView: View {
        @EnvironmentObject var store: RayonStore
        @State private var searchKey = ""
        @State private var openCreate = false

        var filtered: [RDIdentity] {
            let all = store.identities
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
                if store.identities.isEmpty {
                    EmptyStateView(
                        "No identities yet",
                        systemImage: "person",
                        message: "A username with a password or key.",
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
                                        EditIdentityView(requestIdentity: identity.id)
                                    } label: {
                                        IdentityRow(identity: identity)
                                    }
                                    .rxListRow()
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            IdentityActions.delete(identity.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            IdentityActions.duplicate(identity.id)
                                        } label: {
                                            Label("Duplicate", systemImage: "plus.square.on.square")
                                        }
                                    }
                                    .contextMenu {
                                        IdentityMenuItems(identity: identity)
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

    /// Deploy Public Key, Copy Public Key, Duplicate; Delete.
    private struct IdentityMenuItems: View {
        let identity: RDIdentity

        var body: some View {
            let publicKey = identity.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !publicKey.isEmpty {
                Section {
                    Button {
                        IdentityActions.deployPublicKey(publicKey, identityID: identity.id)
                    } label: {
                        Label("Deploy Public Key (ssh-copy-id)…", systemImage: "square.and.arrow.up.on.square")
                    }
                    Button {
                        Pasteboard.copy(publicKey)
                    } label: {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }
                }
            }
            Button {
                IdentityActions.duplicate(identity.id)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                IdentityActions.delete(identity.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @MainActor
    enum IdentityActions {
        static func duplicate(_ id: RDIdentity.ID) {
            guard var copy = RayonStore.shared.identity(id) else { return }
            copy.id = UUID()
            copy.comment = copy.comment.isEmpty ? "Copy" : copy.comment + " (copy)"
            RayonStore.shared.save(copy)
        }

        @MainActor
        static func delete(_ id: RDIdentity.ID, onDeleted: (() -> Void)? = nil) {
            let store = RayonStore.shared
            guard let identity = store.identity(id) else { return }
            let users = store.machines.filter { $0.associatedIdentity == id }.count
            Indicator.confirm(
                message: "Delete identity \(identity.username)?",
                informative: users > 0
                    ? "\(users) server\(users == 1 ? "" : "s") use it and will try automatic identities instead."
                    : "Its password and keys are removed from Rayon.",
                confirmTitle: "Delete",
                destructive: true
            ) { confirmed in
                guard confirmed else { return }
                store.deleteIdentities([id])
                onDeleted?()
            }
        }

        /// ssh-copy-id: pick servers, then append the public key to each one's
        /// ~/.ssh/authorized_keys. Servers that sign in automatically take the
        /// identity once every server has the key.
        @MainActor
        static func deployPublicKey(_ publicKey: String, identityID: RDIdentity.ID) {
            let pub = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pub.isEmpty else {
                Indicator.error("This identity has no public key to deploy.")
                return
            }
            Task { @MainActor in
                let machines = await RayonUtil.selectMachine()
                guard !machines.isEmpty else { return }
                Indicator.success(
                    "Deploying public key",
                    message: machines.count == 1 ? "To 1 server" : "To \(machines.count) servers"
                )
                Task {
                    let outcome = await PublicKeyDeployment.deploy(pub, to: machines)
                    await MainActor.run {
                        if !outcome.failed.isEmpty {
                            Indicator.error("Failed to deploy public key to: \(outcome.failed.joined(separator: ", ")).")
                        } else if !outcome.succeeded.isEmpty {
                            PublicKeyDeployment.adopt(identity: identityID, on: machines)
                            Indicator.success(
                                "Public key deployed",
                                message: outcome.succeeded.joined(separator: ", ")
                            )
                        }
                    }
                }
            }
        }
    }

    private struct IdentityRow: View {
        let identity: RDIdentity
        @EnvironmentObject var store: RayonStore

        var usage: Int {
            store.machines.filter { $0.associatedIdentity == identity.id }.count
        }

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.username.isEmpty ? "No username" : identity.username)
                        .foregroundStyle(identity.username.isEmpty ? Color.rxInkSecondary : Color.rxInk)
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

#endif
