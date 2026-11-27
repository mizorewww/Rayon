//
//  IdentityPicker.swift
//  Rayon
//
//  The identity a new server signs in with, when none signs in on its own:
//  a Table on the Mac, a List on iPhone and iPad, and New Identity.
//

import RayonModule
import SwiftUI

struct IdentityPicker: View {
    /// Hears the identity chosen; nil when cancelled.
    let onComplete: (RDIdentity.ID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RayonStore.shared
    @State private var selection: RDIdentity.ID?
    @State private var creating = false
    @State private var sortOrder = [KeyPathComparator(\RDIdentity.username, comparator: .localizedStandard)]

    var body: some View {
        identities
            .overlay {
                if store.identities.isEmpty {
                    ContentUnavailableView {
                        Label("No identities yet", systemImage: "person")
                    } actions: {
                        Button("New Identity") { creating = true }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onComplete(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") {
                        dismiss()
                        onComplete(selection)
                    }
                    .disabled(selection == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Identity", systemImage: "plus") { creating = true }
                }
            }
            .editorSheet("Choose Identity")
            .sheet(isPresented: $creating) {
                IdentityEditor(identity: nil) { created in selection = created }
            }
    }

    #if os(macOS)
        private var identities: some View {
            Table(store.identities.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Username", value: \.username, comparator: .localizedStandard) { identity in
                    Text(identity.username)
                }
                TableColumn("Authentication") { identity in
                    Text(identity.authDescription).foregroundStyle(.rxInkSecondary)
                }
                TableColumn("Group", value: \.group, comparator: .localizedStandard) { identity in
                    Text(identity.group).foregroundStyle(.rxInkSecondary)
                }
            }
            .frame(minHeight: 260)
        }
    #else
        private var identities: some View {
            List(store.identities.sorted(using: sortOrder), selection: $selection) { identity in
                IdentityRow(identity: identity)
            }
            .environment(\.editMode, .constant(.active))
        }
    #endif
}
