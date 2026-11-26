//
//  LegacyBackup.swift
//  RayonModule
//
//  The backups 2.7 and 2.8 exported: their records as JSON, or that JSON
//  sealed ("RGCM2") with a key derived from a passphrase. They are read
//  with the previous release's record types, as the legacy import reads
//  its store, and restored like any backup.
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
}
