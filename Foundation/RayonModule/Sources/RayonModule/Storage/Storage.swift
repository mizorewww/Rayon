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

    /// Writes the record. A change to what syncs marks it changed now and
    /// queues it for iCloud; a change to this device's own fields alone does
    /// neither. Returns the record as written.
    @discardableResult
    func save<T: StoredRecord>(_ record: T) throws -> T {
        var record = record
        let existing = row(T.self, id: record.id).map(withSecrets)
        if let existing, !existing.removed, !record.differsInSyncedContent(from: existing) {
            record.modified = existing.modified
            record.removed = false
            try db.insertOrReplace([record], intoTable: T.tableName)
            return record
        }
        record.modified = Date().wholeMilliseconds
        record.removed = false
        try writeSecrets(of: record)
        try db.run(transaction: { handle in
            try handle.insertOrReplace([record], intoTable: T.tableName)
            try self.enqueueUpload(T.self, id: record.id, modified: record.modified, handle: handle)
        })
        return record
    }

    /// Marks the records deleted, forgets their secrets and queues the
    /// deletions for iCloud.
    func delete<T: StoredRecord>(_: T.Type, ids: [UUID]) throws {
        let now = Date().wholeMilliseconds
        var deleted: [T] = []
        for id in ids {
            guard var row = row(T.self, id: id), !row.removed else { continue }
            row.removed = true
            row.modified = now
            row.secrets = .init()
            deleted.append(row)
        }
        guard !deleted.isEmpty else { return }
        try db.run(transaction: { handle in
            try handle.insertOrReplace(deleted, intoTable: T.tableName)
            for row in deleted {
                try self.enqueueUpload(T.self, id: row.id, modified: now, handle: handle)
            }
        })
        for row in deleted {
            try? secrets.remove(row.secretAccount)
        }
    }

    /// Whether any record was ever written, deleted ones included.
    var hasAnyRecord: Bool {
        func any<T: StoredRecord>(_: T.Type) -> Bool {
            ((try? db.getValue(on: Column(named: "id").count(), fromTable: T.tableName))?.intValue ?? 0) > 0
        }
        return Self.recordTypes.contains { any($0) }
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

extension RayonStorage {
    /// Every kind of record, in the order a backup or a full upload writes
    /// them (folders before the servers in them).
    static let recordTypes: [any StoredRecord.Type] = [
        RDFolder.self, RDIdentity.self, RDMachine.self, RDSnippet.self, RDPortForward.self,
    ]

    /// The row, deleted or not, without its secrets.
    func row<T: StoredRecord>(_: T.Type, id: UUID) -> T? {
        try? db.getObject(fromTable: T.tableName, where: idColumn == id.uuidString)
    }

    func withSecrets<T: StoredRecord>(_ row: T) -> T {
        guard T.Secrets.self != NoSecrets.self else { return row }
        var row = row
        do {
            row.secrets = try secrets.value(T.Secrets.self, for: row.secretAccount) ?? .init()
        } catch {
            Self.logger.error("reading the secrets of \(row.secretAccount) failed: \(error.localizedDescription)")
        }
        return row
    }

    func writeSecrets<T: StoredRecord>(of record: T) throws {
        guard T.Secrets.self != NoSecrets.self else { return }
        if record.secrets == T.Secrets() {
            try secrets.remove(record.secretAccount)
        } else {
            try secrets.setValue(record.secrets, for: record.secretAccount)
        }
    }
}
