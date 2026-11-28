//
//  IdentitiesView+iOS.swift
//  Rayon
//
//  Identities in sections by group; a tap edits one.
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    struct IdentitiesView: View {
        @EnvironmentObject var store: RayonStore
        @State private var searchText = ""

        private var groups: [(name: String, identities: [RDIdentity])] {
            let key = searchText.lowercased()
            let matching = store.identities.filter {
                key.isEmpty || [$0.username, $0.group, $0.comment].contains { $0.lowercased().contains(key) }
            }
            // Default last.
            let names = Set(matching.map(\.group)).sorted { lhs, rhs in
                if lhs.isEmpty { return false }
                if rhs.isEmpty { return true }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            return names.map { name in
                (name, matching.filter { $0.group == name }.sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending })
            }
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
                        IdentityActions.edit(nil)
                    }
                    .frame(maxHeight: .infinity)
                    .background(RXBackdrop().ignoresSafeArea())
                } else {
                    List {
                        ForEach(groups, id: \.name) { group in
                            Section {
                                ForEach(group.identities) { identity in
                                    Button {
                                        IdentityActions.edit(identity.id)
                                    } label: {
                                        IdentityRow(identity: identity)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .rxListRow()
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            IdentityActions.delete([identity.id])
                                        }
                                        Button("Duplicate", systemImage: "plus.square.on.square") {
                                            IdentityActions.duplicate(identity.id)
                                        }
                                    }
                                    .contextMenu { IdentityContextMenu(identity: identity.id) }
                                }
                            } header: {
                                RXSectionHeader(group.name.isEmpty ? "Default" : "\(group.name)")
                            }
                        }
                    }
                    .rxGroupedList()
                    .searchable(text: $searchText, prompt: "Search identities")
                    .overlay {
                        if groups.isEmpty { ContentUnavailableView.search(text: searchText) }
                    }
                }
            }
            .navigationTitle("Identities")
            .toolbar {
                ToolbarItem {
                    Button("New Identity", systemImage: "plus") { IdentityActions.edit(nil) }
                }
            }
        }
    }

#endif
