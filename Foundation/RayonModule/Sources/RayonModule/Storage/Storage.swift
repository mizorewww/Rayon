//
//  Storage.swift
//  RayonModule
//
//  The database: one WCDB (SQLite) file with a table per kind of record,
//  migrated one schema version at a time (`PRAGMA user_version`), after
//  FlowDown's Storage. Thread-safe; the main-actor `RayonStore` publishes
//  what it holds to the interface.
//

import Foundation
import os
import Synchronization
@preconcurrency import WCDBSwift

public final class RayonStorage: Sendable {
    /// How long a deleted record is remembered, so that a device that has
    /// not synced for a while learns of the deletion instead of bringing the
    /// record back.
    static let tombstoneLifetime: TimeInterval = 60 * 60 * 24 * 30

    static let logger = Logger(subsystem: "me.mizorewww.rayon", category: "storage")

    public static let shared: RayonStorage = openDefault()

    let db: Database
    let secrets: SecretStore
    /// Saves, deletions and merges from iCloud one at a time: each reads the
    /// record, decides, then writes it and its secrets, and must not do so
    /// on a version another one is replacing.
    let writes = Mutex(())
    public let databaseURL: URL

    public init(databaseURL: URL, secrets: SecretStore = .shared) throws {
        self.databaseURL = databaseURL
        self.secrets = secrets
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        db = Database(at: databaseURL.path)
        db.setAutoBackup(enable: true)
        try DBMigration.migrate(db)
    }

    /// Where the app keeps its database: its own Application Support folder,
    /// apart for the Debug and Release builds of the Mac app.
    public static var defaultDatabaseURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "me.mizorewww.rayon", directoryHint: .isDirectory)
            .appending(path: "Storage", directoryHint: .isDirectory)
            .appending(path: "database.db")
    }

    /// A database that cannot be opened is moved aside, kept for recovery,
    /// and a new one is made in its place.
    private static func openDefault() -> RayonStorage {
        let url = defaultDatabaseURL
        do {
            return try RayonStorage(databaseURL: url)
        } catch {
            logger.error("unable to open the database at \(url.path): \(error.localizedDescription)")
            let aside = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).db")
            try? FileManager.default.moveItem(at: url, to: aside)
            do {
                return try RayonStorage(databaseURL: url)
            } catch {
                fatalError("unable to create a database at \(url.path): \(error)")
            }
        }
    }

    /// Closes the database; nothing is read or written after.
    func close() {
        db.close()
    }
}

// MARK: - Records

private let idColumn = Column(named: "id")
private let removedColumn = Column(named: "removed")
private let modifiedColumn = Column(named: "modified")

public extension RayonStorage {
    /// Every record of the kind that is not deleted.
    func records<T: StoredRecord>(_: T.Type) -> [T] {
        do {
            let rows: [T] = try db.getObjects(fromTable: T.tableName, where: removedColumn == false)
            return rows.map(withSecrets)
        } catch {
            Self.logger.error("reading \(T.tableName) failed: \(error.localizedDescription)")
            return []
        }
    }

    func record<T: StoredRecord>(_: T.Type, id: UUID) -> T? {
        guard let row = row(T.self, id: id), !row.removed else { return nil }
        return withSecrets(row)
    }

    /// Writes the record. A change to what syncs marks it changed (now,
    /// unless `changed` says when) and queues it for iCloud; a change to this
    /// device's own fields alone does neither. Returns the record as written.
    @discardableResult
    func save<T: StoredRecord>(_ record: T, changed: Date? = nil) throws -> T {
        try writes.withLock { _ in try saveLocked(record, changed: changed) }
    }

    private func saveLocked<T: StoredRecord>(_ record: T, changed: Date?) throws -> T {
        var record = record
        let existing = row(T.self, id: record.id).map(withSecrets)
        if record.secretsUnread {
            if record.secrets == T.Secrets(), let existing {
                // Nothing typed in their place: the keychain's stay, read
                // now if it gives them.
                record.secrets = existing.secrets
                record.secretsUnread = existing.secretsUnread
            } else {
                // New ones typed in: they are written.
                record.secretsUnread = false
            }
        }
        if let existing, !existing.removed, !record.differsInSyncedContent(from: existing) {
            record.modified = existing.modified
            record.removed = false
            try db.insertOrReplace([record], intoTable: T.tableName)
            return record
        }
        record.modified = Self.stamp(changed ?? Date(), after: existing)
        record.removed = false
        let present = try writeSecrets(of: record)
        try db.run(transaction: { handle in
            try handle.insertOrReplace([record], intoTable: T.tableName)
            try self.notePresence(present, of: record, handle: handle)
            try self.enqueueUpload(T.self, id: record.id, modified: record.modified, handle: handle)
        })
        NotificationCenter.default.post(name: Self.didQueueChanges, object: self)
        return record
    }

    /// Marks the records deleted, forgets their secrets and queues the
    /// deletions for iCloud.
    func delete<T: StoredRecord>(_: T.Type, ids: [UUID]) throws {
        try writes.withLock { _ in try deleteLocked(T.self, ids: ids) }
    }

    private func deleteLocked<T: StoredRecord>(_: T.Type, ids: [UUID]) throws {
        let now = Date()
        var deleted: [T] = []
        for id in ids {
            guard var row = row(T.self, id: id), !row.removed else { continue }
            row.modified = Self.stamp(now, after: row)
            row.removed = true
            row.secrets = .init()
            deleted.append(row)
        }
        guard !deleted.isEmpty else { return }
        try db.run(transaction: { handle in
            try handle.insertOrReplace(deleted, intoTable: T.tableName)
            for row in deleted {
                try self.notePresence(false, of: row, handle: handle)
                try self.enqueueUpload(T.self, id: row.id, modified: row.modified, handle: handle)
            }
        })
        for row in deleted {
            try? secrets.remove(row.secretAccount)
        }
        NotificationCenter.default.post(name: Self.didQueueChanges, object: self)
    }

    /// Forgets the deletions older than the tombstone lifetime that have
    /// nothing left to send.
    func purgeTombstones(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.tombstoneLifetime)
        for type in Self.recordTypes {
            purgeTombstones(type, before: cutoff)
        }
    }

    private func purgeTombstones<T: StoredRecord>(_: T.Type, before cutoff: Date) {
        let queued = Set(((try? db.getObjects(
            fromTable: UploadQueueEntry.tableName,
            where: UploadQueueEntry.Properties.tableName == T.tableName
        )) as [UploadQueueEntry]?)?.map(\.objectId) ?? [])
        let stale: [T] = (try? db.getObjects(
            fromTable: T.tableName,
            where: removedColumn == true && modifiedColumn < cutoff
        )) ?? []
        let ids = stale.map(\.id).filter { !queued.contains($0) }
        guard !ids.isEmpty else { return }
        try? db.delete(fromTable: T.tableName, where: idColumn.in(ids.map(\.uuidString)))
    }
}

/// Writes for `RayonStorage.insertMissing`, inside its transaction.
final class RecordInserter {
    private let storage: RayonStorage
    let handle: Handle
    /// The keychain items written, to remove if the transaction fails.
    private(set) var secretAccounts: [String] = []

    fileprivate init(storage: RayonStorage, handle: Handle) {
        self.storage = storage
        self.handle = handle
    }

    func insert<T: StoredRecord>(_ record: T, modified: Date) throws {
        let existing: T? = try handle.getObject(fromTable: T.tableName, where: idColumn == record.id.uuidString)
        guard existing == nil else { return }
        var record = record
        record.modified = modified.wholeMilliseconds
        record.removed = false
        if T.Secrets.self != NoSecrets.self, record.secrets != T.Secrets() {
            secretAccounts.append(record.secretAccount)
            try storage.secrets.setValue(record.secrets, for: record.secretAccount)
            try storage.notePresence(true, of: record, handle: handle)
        }
        try handle.insert([record], intoTable: T.tableName)
        try storage.enqueueUpload(T.self, id: record.id, modified: record.modified, handle: handle)
    }
}

extension RayonStorage {
    /// Every kind of record, in the order a backup or a full upload writes
    /// them (folders before the servers in them).
    static let recordTypes: [any StoredRecord.Type] = [
        RDFolder.self, RDIdentity.self, RDMachine.self, RDSnippet.self, RDPortForward.self, RDTerminalSettings.self,
    ]

    /// Adds records that are not here yet (a deleted one counts as here)
    /// and queues them for iCloud, all in one transaction: when anything
    /// fails, nothing is kept, the secrets written to the keychain included.
    func insertMissing(_ write: (RecordInserter) throws -> Void) throws {
        try writes.withLock { _ in try insertMissingLocked(write) }
    }

    private func insertMissingLocked(_ write: (RecordInserter) throws -> Void) throws {
        var inserter: RecordInserter?
        do {
            try withoutActuallyEscaping(write) { write in
                try db.run(transaction: { handle in
                    let current = RecordInserter(storage: self, handle: handle)
                    inserter = current
                    try write(current)
                })
            }
        } catch {
            for account in inserter?.secretAccounts ?? [] {
                try? secrets.remove(account)
            }
            throw error
        }
        NotificationCenter.default.post(name: Self.didQueueChanges, object: self)
    }

    /// When a change made at `date` counts as made: after the version it
    /// changes, even when that one came from a device whose clock is ahead,
    /// so that the change wins over it everywhere.
    static func stamp<T: StoredRecord>(_ date: Date, after existing: T?) -> Date {
        let date = date.wholeMilliseconds
        guard let existing, existing.modified >= date else { return date }
        return Date(timeIntervalSince1970: TimeInterval(existing.modified.millisecondsSince1970 + 1) / 1000)
    }

        /// The row, deleted or not, without its secrets.
    func row<T: StoredRecord>(_: T.Type, id: UUID) -> T? {
        try? db.getObject(fromTable: T.tableName, where: idColumn == id.uuidString)
    }

    /// The row with its secrets from the keychain, or marked unread when
    /// the keychain does not give them.
    func withSecrets<T: StoredRecord>(_ row: T) -> T {
        guard T.Secrets.self != NoSecrets.self, !row.removed else { return row }
        var row = row
        do {
            if let value = try secrets.value(T.Secrets.self, for: row.secretAccount) {
                row.secrets = value
                // Rows saved before the database noted this learn it here.
                if !hasSecrets(row) { try? db.insertOrReplace([SecretPresence(account: row.secretAccount)], intoTable: SecretPresence.tableName) }
            } else if hasSecrets(row) {
                Self.logger.error("the secrets of \(row.secretAccount) are missing from the keychain")
                row.secretsUnread = true
            }
        } catch {
            Self.logger.error("reading the secrets of \(row.secretAccount) failed: \(error.localizedDescription)")
            row.secretsUnread = true
        }
        return row
    }

    private func hasSecrets<T: StoredRecord>(_ row: T) -> Bool {
        ((try? db.getObject(fromTable: SecretPresence.tableName, where: SecretPresence.Properties.account == row.secretAccount)) as SecretPresence?) != nil
    }

    /// Writes the record's secrets to the keychain, unless they were never
    /// read. Returns whether the record has secrets now, for
    /// `notePresence`; nil when nothing was written.
    func writeSecrets<T: StoredRecord>(of record: T) throws -> Bool? {
        guard T.Secrets.self != NoSecrets.self, !record.secretsUnread else { return nil }
        if record.secrets == T.Secrets() {
            try secrets.remove(record.secretAccount)
            return false
        }
        try secrets.setValue(record.secrets, for: record.secretAccount)
        return true
    }

    /// Notes in the database whether the record's secrets are in the
    /// keychain; nil leaves it as it is.
    func notePresence<T: StoredRecord>(_ present: Bool?, of record: T, handle: Handle) throws {
        guard T.Secrets.self != NoSecrets.self, let present else { return }
        if present {
            try handle.insertOrReplace([SecretPresence(account: record.secretAccount)], intoTable: SecretPresence.tableName)
        } else {
            try handle.delete(fromTable: SecretPresence.tableName, where: SecretPresence.Properties.account == record.secretAccount)
        }
    }
}
