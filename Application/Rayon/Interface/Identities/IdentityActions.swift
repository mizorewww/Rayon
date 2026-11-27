//
//  IdentityActions.swift
//  Rayon
//
//  What can be done to identities, the menu that offers it, and the row
//  an identity has in a list.
//

import RayonModule
import SwiftUI

@MainActor
enum IdentityActions {
    /// New Identity, or the identity's editor; `onSaved` hears the identity
    /// saved.
    static func edit(_ id: RDIdentity.ID?, onSaved: ((RDIdentity.ID) -> Void)? = nil) {
        let editor = IdentityEditor(identity: id, onSaved: onSaved)
        #if os(macOS)
            AppRouter.shared.present { _ in editor }
        #else
            RayonUtil.presentModalSheet(rootView: editor)
        #endif
    }

    static func duplicate(_ id: RDIdentity.ID) {
        guard var copy = RayonStore.shared.identity(id) else { return }
        copy.id = UUID()
        copy.comment = copy.comment.isEmpty ? String(localized: "Copy (identity comment)", defaultValue: "Copy", comment: "The comment of a duplicated identity that had none") : String(localized: "\(copy.comment) (copy)")
        RayonStore.shared.save(copy)
    }

    static func delete(_ ids: [RDIdentity.ID], onDeleted: (() -> Void)? = nil) {
        let store = RayonStore.shared
        guard let first = ids.first.flatMap({ store.identity($0) }) else { return }
        let users = store.machines.filter { $0.associatedIdentity.map(ids.contains) ?? false }.count
        Indicator.confirm(
            message: ids.count == 1 ? "Delete identity \(first.username)?" : "Delete \(ids.count) identities?",
            informative: users > 0
                ? "\(users) servers use it and will try automatic identities instead."
                : "Its password and keys are removed from Rayon.",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            store.deleteIdentities(ids)
            onDeleted?()
        }
    }

    /// ssh-copy-id: pick servers, then append the public key to each one's
    /// ~/.ssh/authorized_keys. Servers that sign in automatically take the
    /// identity once every server has the key.
    static func deployPublicKey(_ publicKey: String, identityID: RDIdentity.ID) {
        let pub = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pub.isEmpty else {
            Indicator.error(String(localized: "This identity has no public key to deploy."))
            return
        }
        ServerPicker.present(
            title: "Deploy Public Key (ssh-copy-id)",
            lead: "Appends this identity's public key to ~/.ssh/authorized_keys on the selected servers.",
            confirmTitle: "Deploy"
        ) { machines in
            #if os(iOS)
                Indicator.success("Deploying public key", message: "To \(machines.count) servers")
            #endif
            Task { @MainActor in
                let outcome = await PublicKeyDeployment.deploy(pub, to: machines)
                if !outcome.failed.isEmpty {
                    Indicator.error(String(localized: "Failed to deploy public key to: \(outcome.failed.joined(separator: ", "))."))
                } else if !outcome.succeeded.isEmpty {
                    PublicKeyDeployment.adopt(identity: identityID, on: machines)
                    #if os(iOS)
                        Indicator.success("Public key deployed", message: "\(outcome.succeeded.joined(separator: ", "))")
                    #endif
                }
            }
        }
    }
}

/// Edit (on the Mac, where a click only selects); Deploy Public Key, Copy
/// Public Key, Duplicate; Delete.
struct IdentityContextMenu: View {
    let identity: RDIdentity.ID

    var body: some View {
        let read = RayonStore.shared.identity(identity) ?? RDIdentity()
        let publicKey = read.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(macOS)
            Button("Edit…", systemImage: "pencil") { IdentityActions.edit(identity) }
        #endif
        if !publicKey.isEmpty {
            Section {
                Button("Deploy Public Key (ssh-copy-id)…", systemImage: "square.and.arrow.up.on.square") {
                    IdentityActions.deployPublicKey(publicKey, identityID: identity)
                }
                Button("Copy Public Key", systemImage: "doc.on.doc") { Pasteboard.copy(publicKey) }
            }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { IdentityActions.duplicate(identity) }
        Section {
            Button("Delete…", systemImage: "trash", role: .destructive) { IdentityActions.delete([identity]) }
        }
    }
}

/// Username, how it signs in, and how many servers use it.
struct IdentityRow: View {
    let identity: RDIdentity
    @ObservedObject private var store = RayonStore.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.username.isEmpty ? "No username" : "\(identity.username)")
                    .foregroundStyle(identity.username.isEmpty ? Color.rxInkSecondary : Color.rxInk)
                Text(identity.authenticAutomatically ? "\(identity.authDescription) · Automatic" : "\(identity.authDescription)")
                    .font(.caption)
                    .foregroundStyle(.rxInkSecondary)
            }
            Spacer()
            Text("\(store.servers(using: identity.id).count) servers")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.rxInkSecondary)
        }
    }
}
