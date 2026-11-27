//
//  RayonStore+Folder.swift
//  RayonModule
//
//  Folder operations. A server names its folder by id; nil is the default
//  folder, which has no record.
//

import Foundation

public extension RayonStore {
    func folder(named name: String) -> RDFolder? {
        folders.first { $0.name == name }
    }

    func machines(inFolder id: RDFolder.ID?) -> [RDMachine] {
        // A server whose folder is gone (deleted on another device, say)
        // is in the default one, where it can be seen.
        machines.filter { folder($0.folderId)?.id == id }
    }

    /// The name of the server's folder; empty for the default one.
    func folderName(of machine: RDMachine) -> String {
        folder(machine.folderId)?.name ?? ""
    }

    /// The folder an editor's folder name stands for: none (the default
    /// folder) for an empty name, else the folder of that name, made when
    /// there is none.
    func folderId(forName name: String) -> RDFolder.ID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (folder(named: name) ?? createFolder(named: name)).id
    }

    /// A folder name not yet taken: `base`, else "base 2", "base 3"…
    func availableFolderName(_ base: String) -> String {
        let taken = Set(folders.map(\.name))
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// Adds an empty folder and returns it; the name is made unique.
    @discardableResult
    func createFolder(named name: String, source: RDFolder.Source = .local) -> RDFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = RDFolder(name: availableFolderName(trimmed.isEmpty ? String(localized: "New Folder", bundle: .module) : trimmed), source: source)
        save(folder)
        return self.folder(folder.id) ?? folder
    }

    /// Renames a folder. False when the new name is empty or taken by
    /// another folder.
    @discardableResult
    func renameFolder(_ id: RDFolder.ID, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = folder(id) else { return false }
        if name == folder.name { return true }
        guard self.folder(named: name) == nil else { return false }
        return updateFolder(folder.id) { $0.name = name } != nil
    }

    /// Removes a folder. Servers pulled from an account go with it; every
    /// other server in it moves to the default folder. Unlinking the account,
    /// so a refresh does not bring the folder back, is the caller's part.
    func deleteFolder(_ id: RDFolder.ID) {
        let inside = machines(inFolder: id)
        deleteMachines(inside.filter(\.uuManaged).map(\.id))
        moveServers(inside.filter { !$0.uuManaged }.map(\.id), toFolder: nil)
        remove(RDFolder.self, ids: [id], from: \.folders)
    }

    /// Puts servers in a folder (nil is the default one).
    func moveServers(_ ids: [RDMachine.ID], toFolder folderId: RDFolder.ID?) {
        for id in ids {
            updateMachine(id) { $0.folderId = folderId }
        }
    }
}
