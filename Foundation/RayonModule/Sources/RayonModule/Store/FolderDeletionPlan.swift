//
//  FolderDeletionPlan.swift
//  RayonModule
//
//  What deleting a folder does, for the confirmation both apps show, and
//  doing it. The signed-in UU Remote account's folder is deleted by signing
//  out, or the next refresh would make it again.
//

import Foundation

@MainActor
public struct FolderDeletionPlan {
    public let folder: RDFolder
    /// Deleting it signs out of UU Remote.
    public let unlinksAccount: Bool
    public let message: String
    /// The consequences, when there are any.
    public let informative: String?
    public let confirmTitle: String

    public init(folder: RDFolder, store: RayonStore = .shared, account: UURemoteAccount = .shared) {
        self.folder = folder
        unlinksAccount = account.isLoggedIn && folder.id == account.folder(store: store)?.id
        let count = store.machines(inFolder: folder.id).count
        var consequences: [String] = []
        if unlinksAccount { consequences.append(String(localized: "Rayon signs out of UU Remote; the devices stay on the account.", bundle: .module)) }
        if count > 0 { consequences.append(String(localized: "Servers you added to it by hand move to Default.", bundle: .module)) }
        message = String(localized: "Delete the folder \"\(folder.name)\"?", bundle: .module)
        informative = consequences.isEmpty ? nil : consequences.joined(separator: " ")
        confirmTitle = unlinksAccount ? String(localized: "Delete and Sign Out", bundle: .module) : String(localized: "Delete Folder", bundle: .module)
    }

    public func perform(store: RayonStore = .shared, account: UURemoteAccount = .shared) {
        if unlinksAccount { account.logout() }
        store.deleteFolder(folder.id)
    }
}
