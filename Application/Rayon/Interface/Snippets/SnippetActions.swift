//
//  SnippetActions.swift
//  Rayon
//
//  What can be done to snippets, and the menu that offers it.
//

import RayonModule
import SwiftUI

@MainActor
enum SnippetActions {
    /// New Snippet, or the snippet's editor.
    static func edit(_ id: RDSnippet.ID?) {
        #if os(macOS)
            AppRouter.shared.present { _ in SnippetEditor(snippet: id) }
        #else
            RayonUtil.presentModalSheet(rootView: SnippetEditor(snippet: id))
        #endif
    }

    /// Picks servers, then runs the snippet on each of them.
    static func run(_ id: RDSnippet.ID) {
        guard let snippet = RayonStore.shared.snippet(id) else { return }
        guard !snippet.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Indicator.error(String(localized: "This snippet has no command to run."))
            return
        }
        // A server on Automatic signs in with the identities that authenticate
        // automatically; it can't when there are none.
        let store = RayonStore.shared
        let cannotSignIn = store.identitiesForAutoAuth.isEmpty && store.machines.contains { $0.associatedIdentity == nil }
        ServerPicker.present(
            title: "Run \(snippet.name)",
            lead: cannotSignIn ? "Servers on Automatic need an identity that authenticates automatically." : nil,
            confirmTitle: "Run"
        ) { machines in
            #if os(macOS)
                AppRouter.shared.present { dismiss in
                    BatchRunSheet(snippet: snippet, machines: machines, close: dismiss)
                }
            #else
                RayonUtil.presentModalSheet(rootView: NavigationStack {
                    SnippetExecuteView(snippet: snippet, machines: machines)
                })
            #endif
        }
    }

    static func duplicate(_ id: RDSnippet.ID) {
        guard var copy = RayonStore.shared.snippet(id) else { return }
        copy.id = UUID()
        copy.name = String(localized: "\(copy.name) copy")
        RayonStore.shared.save(copy)
    }

    static func delete(_ id: RDSnippet.ID, onDeleted: (() -> Void)? = nil) {
        guard let snippet = RayonStore.shared.snippet(id) else { return }
        Indicator.confirm(
            message: snippet.name.isEmpty ? "Delete this snippet?" : "Delete \(snippet.name)?",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            RayonStore.shared.deleteSnippets([id])
            onDeleted?()
        }
    }
}

/// Run, Edit, Duplicate, Copy Command; Delete.
struct SnippetMenuItems: View {
    let snippet: RDSnippet

    var body: some View {
        Button("Run…", systemImage: "play") { SnippetActions.run(snippet.id) }
        Button("Edit…", systemImage: "pencil") { SnippetActions.edit(snippet.id) }
        Button("Duplicate", systemImage: "plus.square.on.square") { SnippetActions.duplicate(snippet.id) }
        Button("Copy Command", systemImage: "doc.on.doc") { Pasteboard.copy(snippet.code) }
        Section {
            Button("Delete…", systemImage: "trash", role: .destructive) { SnippetActions.delete(snippet.id) }
        }
    }
}
