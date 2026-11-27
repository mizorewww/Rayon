//
//  IdentitiesView+macOS.swift
//  Rayon
//
//  Identities in a Table: sortable columns, several selected at once for
//  Delete, a double click or Return to edit.
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    struct IdentitiesView: View {
        @EnvironmentObject var store: RayonStore
        @State private var searchText = ""
        @State private var selection = Set<RDIdentity.ID>()
        @State private var sortOrder = [KeyPathComparator(\RDIdentity.username, comparator: .localizedStandard)]

        private var identities: [RDIdentity] {
            let key = searchText.lowercased()
            return store.identities
                .filter {
                    key.isEmpty || [$0.username, $0.group, $0.comment].contains { $0.lowercased().contains(key) }
                }
                .sorted(using: sortOrder)
        }

        var body: some View {
            PageScaffold(
                scrolls: false,
                search: $searchText,
                searchPrompt: "Search identities",
                primary: ToolbarAction("New Identity", systemImage: "plus", primary: true) { create() }
            ) {
            } trailing: {
            } header: {
                PageTitle("Identities")
            } content: {
                if store.identities.isEmpty {
                    EmptyStateView(
                        "No identities yet",
                        systemImage: "person",
                        message: "A username with a password or key.",
                        actionTitle: "New Identity"
                    ) {
                        create()
                    }
                    .rxCard()
                } else {
                    table
                }
            }
            // Edit › Delete… (⌘⌫) deletes the selected rows.
            .focusedSceneValue(\.deleteSelection, selection.isEmpty ? nil : { IdentityActions.delete(Array(selection)) })
        }

        private var table: some View {
            Table(identities, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Username", value: \.username, comparator: .localizedStandard) { identity in
                    Text(identity.username.isEmpty ? "No username" : "\(identity.username)")
                        .foregroundStyle(identity.username.isEmpty ? Color.rxInkSecondary : Color.rxInk)
                }
                TableColumn("Authentication") { identity in
                    Text(identity.authDescription)
                        .foregroundStyle(.rxInkSecondary)
                }
                TableColumn("Group", value: \.group, comparator: .localizedStandard) { identity in
                    Text(identity.group.isEmpty ? "Default" : "\(identity.group)")
                        .foregroundStyle(.rxInkSecondary)
                }
                TableColumn("Automatic", value: \.authenticAutomatically.sortKey) { identity in
                    Text(identity.authenticAutomatically ? "Yes" : "No")
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Servers") { identity in
                    Text("\(store.serverCount(using: identity.id))")
                        .monospacedDigit()
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 50, ideal: 60)
            }
            .contextMenu(forSelectionType: RDIdentity.ID.self) { chosen in
                if chosen.count == 1, let identity = chosen.first {
                    IdentityContextMenu(identity: identity)
                } else if !chosen.isEmpty {
                    Button("Delete \(chosen.count) Identities…", systemImage: "trash", role: .destructive) {
                        IdentityActions.delete(Array(chosen))
                    }
                }
            } primaryAction: { chosen in
                if let identity = chosen.first { IdentityActions.edit(identity) }
            }
            .overlay {
                if identities.isEmpty { ContentUnavailableView.search(text: searchText) }
            }
        }

        private func create() {
            IdentityActions.edit(nil) { created in selection = [created] }
        }
    }

    private extension Bool {
        /// Bool is not Comparable; a Table sorts by this instead.
        var sortKey: Int { self ? 1 : 0 }
    }

#endif
