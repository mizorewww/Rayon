//
//  LegacyBackup.swift
//  RayonModule
//
//  The backups 2.7 and 2.8 exported: their records as JSON, or that JSON
//  sealed ("RGCM2") with a key derived from a passphrase; and the data the
//  original app's hidden importer took from the pasteboard: its stored
//  values as a property list, each sealed with a key pasted after it.
//  They are read with the previous release's record types, as the legacy
//  import reads its store, and restored like any backup.
//

import Foundation

enum LegacyBackup {
    struct Archive: Decodable {
        var machines: [LegacyStoreImport.Machine]
        var identities: [LegacyStoreImport.Identity]
        var snippets: [LegacyStoreImport.Snippet]
        var portForwards: [LegacyStoreImport.PortForward]
        var folders: [LegacyStoreImport.Folder]
    }

    static func isSealed(_ data: Data) -> Bool {
        data.starts(with: Data("RGCM".utf8))
    }

    /// The records of the backup in `data`; `notABackup` when it is not one.
    static func read(_ data: Data, password: String?) throws -> DataBackupContents {
        var payload = data
        if isSealed(data) {
            // As 2.8 read them: the passphrase without surrounding spaces.
            let passphrase = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !passphrase.isEmpty else { throw BackupError.passwordRequired }
            guard let plain = LegacyStoreImport.Opener(masterKey: passphrase).open(data) else { throw BackupError.wrongPassword }
            payload = plain
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: payload) else { throw BackupError.notABackup }

        var contents = DataBackupContents(includesSecrets: true)
        var folders = archive.folders.map(\.folder)
        let folderIDs = LegacyStoreImport.addFolders(namedBy: archive.machines, to: &folders)
        contents.folders = folders
        contents.identities = archive.identities.map(\.identity)
        contents.machines = archive.machines.map { $0.machine(folderId: folderIDs[$0.group]) }
        contents.snippets = archive.snippets.map(\.snippet)
        contents.portForwards = archive.portForwards.map(\.forward)
        return contents
    }

    /// The records in pasted data, sealed under `key` in any of the old
    /// formats; `wrongPassword` when the key does not open them.
    static func readPasted(_ data: Data, key: String) throws -> DataBackupContents {
        guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BackupError.notABackup
        }
        let opener = LegacyStoreImport.Opener(masterKey: key)
        func open<T: Decodable>(_ name: String, as _: T.Type) throws -> T? {
            guard let value = values[name] else { return nil }
            guard let sealed = value as? Data,
                  let plain = opener.open(sealed),
                  let decoded = try? PropertyListDecoder().decode(T.self, from: plain)
            else { throw BackupError.wrongPassword }
            return decoded
        }
        typealias Key = LegacyStoreImport.Key
        guard [Key.machines, Key.identities, Key.snippets, Key.portForwards].contains(where: { values[$0] != nil }) else {
            throw BackupError.notABackup
        }
        let machines = try open(Key.machines, as: LegacyStoreImport.MachineGroup.self)?.machines ?? []
        var folders = try (open(Key.folders, as: LegacyStoreImport.FolderGroup.self)?.folders ?? []).map(\.folder)
        let folderIDs = LegacyStoreImport.addFolders(namedBy: machines, to: &folders)
        var contents = DataBackupContents(includesSecrets: true)
        contents.folders = folders
        contents.machines = machines.map { $0.machine(folderId: folderIDs[$0.group]) }
        contents.identities = try (open(Key.identities, as: LegacyStoreImport.IdentityGroup.self)?.identities ?? []).map(\.identity)
        contents.snippets = try (open(Key.snippets, as: LegacyStoreImport.SnippetGroup.self)?.snippets ?? []).map(\.snippet)
        contents.portForwards = try (open(Key.portForwards, as: LegacyStoreImport.PortForwardGroup.self)?.forwards ?? []).map(\.forward)
        return contents
    }
}

public extension RayonStore {
    /// The original app's hidden importer: data copied from it, then the
    /// key it was sealed with, each from the pasteboard. Adds what it holds
    /// as a backup restore does.
    func importPasted(_ data: Data, key: String) throws -> RestoreResult {
        try restore(LegacyBackup.readPasted(data, key: key))
    }
}
