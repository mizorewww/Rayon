//
//  DataBackup.swift
//  RayonModule
//
//  A backup of the user's data: a snapshot of the database (servers,
//  identities, snippets, forwards, folders, known host keys) and, when
//  asked for, their passwords and keys, which then need a password.
//  Restoring adds the backup's records, replacing those with the same id;
//  nothing is written until the whole backup has been read.
//

import Foundation
@preconcurrency import WCDBSwift

public struct DataBackupContents: Sendable {
    public var folders: [RDFolder] = []
    public var identities: [RDIdentity] = []
    public var machines: [RDMachine] = []
    public var snippets: [RDSnippet] = []
    public var portForwards: [RDPortForward] = []
    var knownHosts: [KnownHostRecord] = []
    public var includesSecrets = false
}

public enum DataBackup {
    public static let fileExtension = "rayonbackup"

    static let databaseFile = "database.db"
    static let secretsFile = "secrets.json"

    /// Writes the backup of `storage` to `url`. Passwords and keys go in
    /// only with a password.
    public static func export(
        from storage: RayonStorage,
        to url: URL,
        includeSecrets: Bool,
        password: String?
    ) throws {
        let password = password.flatMap { $0.isEmpty ? nil : $0 }
        if includeSecrets, password == nil { throw BackupError.passwordRequired }

        let folder = try BackupArchive.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshotURL = folder.appendingPathComponent(databaseFile)
        let snapshot = Database(at: snapshotURL.path)
        var secrets: [String: Data] = [:]
        do {
            try DBMigration.migrate(snapshot)
            func copy<T: StoredRecord>(_: T.Type) throws {
                let records = storage.records(T.self)
                try snapshot.insert(records, intoTable: T.tableName)
                guard includeSecrets, T.Secrets.self != NoSecrets.self else { return }
                if records.contains(where: \.secretsUnread) { throw BackupError.secretsUnavailable }
                for record in records where record.secrets != T.Secrets() {
                    secrets[record.secretAccount] = try JSONEncoder().encode(record.secrets)
                }
            }
            for type in RayonStorage.recordTypes {
                try copy(type)
            }
            let hosts: [KnownHostRecord] = try storage.db.getObjects(fromTable: KnownHostRecord.tableName)
            try snapshot.insert(hosts, intoTable: KnownHostRecord.tableName)
            // Everything into the database file itself, which is all that
            // is packed.
            try snapshot.truncateCheckpoint()
        } catch {
            snapshot.close()
            throw error
        }
        snapshot.close()

        var files = [databaseFile: try Data(contentsOf: snapshotURL)]
        if includeSecrets {
            files[secretsFile] = try JSONEncoder().encode(secrets)
        }
        try BackupArchive.write(files, kind: .data, includesSecrets: includeSecrets, password: password, to: url)
    }

    /// Whether opening the backup at `url` needs its password.
    public static func needsPassword(_ url: URL) -> Bool {
        BackupArchive.isEncrypted(url)
    }

    /// Reads the backup at `url` completely; throws on anything wrong
    /// (a wrong password among it) before anything is restored.
    public static func read(_ url: URL, password: String?) throws -> DataBackupContents {
        let (manifest, files) = try BackupArchive.read(url, kind: .data, password: password)
        guard let database = files[databaseFile] else { throw BackupError.damaged("it has no database") }
        let secrets: [String: Data]
        if let data = files[secretsFile] {
            guard let decoded = try? JSONDecoder().decode([String: Data].self, from: data) else {
                throw BackupError.damaged("its passwords and keys cannot be read")
            }
            secrets = decoded
        } else {
            secrets = [:]
        }

        let folder = try BackupArchive.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshotURL = folder.appendingPathComponent(databaseFile)
        try database.write(to: snapshotURL)
        let snapshot = Database(at: snapshotURL.path)
        defer { snapshot.close() }
        guard snapshot.canOpen else { throw BackupError.damaged("its database cannot be opened") }
        do {
            // A snapshot of an older schema is brought up to this one.
            try DBMigration.migrate(snapshot)
        } catch {
            throw BackupError.newerVersion
        }

        func rows<T: StoredRecord>(_: T.Type) throws -> [T] {
            let rows: [T] = try snapshot.getObjects(fromTable: T.tableName, where: Column(named: "removed") == false)
            guard T.Secrets.self != NoSecrets.self else { return rows }
            return try rows.map { row in
                var row = row
                if let data = secrets[row.secretAccount] {
                    guard let value = try? JSONDecoder().decode(T.Secrets.self, from: data) else {
                        throw BackupError.damaged("the passwords of \(T.tableName) \(row.id) cannot be read")
                    }
                    row.secrets = value
                }
                return row
            }
        }
        do {
            return try DataBackupContents(
                folders: rows(RDFolder.self),
                identities: rows(RDIdentity.self),
                machines: rows(RDMachine.self),
                snippets: rows(RDSnippet.self),
                portForwards: rows(RDPortForward.self),
                knownHosts: snapshot.getObjects(fromTable: KnownHostRecord.tableName),
                includesSecrets: manifest.includesSecrets
            )
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.damaged(error.localizedDescription)
        }
    }
}

public extension RayonStore {
    /// Writes a backup of everything saved.
    func exportBackup(to url: URL, includeSecrets: Bool, password: String?) throws {
        try DataBackup.export(from: storage, to: url, includeSecrets: includeSecrets, password: password)
    }

    /// Adds what a backup holds, replacing records with the same id.
    /// Without the backup's passwords and keys, a record already here keeps
    /// its own.
    @discardableResult
    func restore(_ contents: DataBackupContents) -> (machines: Int, identities: Int, snippets: Int, forwards: Int) {
        func merged<T: StoredRecord>(_ record: T, _ existing: T?) -> T {
            guard !contents.includesSecrets, let existing else { return record }
            var record = record
            record.secrets = existing.secrets
            record.secretsUnread = existing.secretsUnread
            return record
        }
        // A folder is known by its name: one of the backup's whose name is
        // taken here becomes that one, rather than a second of the name.
        var folderIDs: [RDFolder.ID: RDFolder.ID] = [:]
        for backup in contents.folders {
            if let existing = folder(named: backup.name), existing.id != backup.id {
                folderIDs[backup.id] = existing.id
            } else {
                save(merged(backup, folder(backup.id)))
                folderIDs[backup.id] = backup.id
            }
        }
        contents.identities.forEach { save(merged($0, identity($0.id))) }
        for var machine in contents.machines {
            // In a folder of the backup, or one here; else the default one,
            // where it can be seen.
            machine.folderId = machine.folderId.flatMap { folderIDs[$0] ?? folder($0)?.id }
            save(merged(machine, self.machine(machine.id)))
        }
        contents.snippets.forEach { save($0) }
        contents.portForwards.forEach { save($0) }
        for host in contents.knownHosts where storage.knownHost(named: host.name) == nil {
            try? storage.saveKnownHost(host)
        }
        return (contents.machines.count, contents.identities.count, contents.snippets.count, contents.portForwards.count)
    }
}
