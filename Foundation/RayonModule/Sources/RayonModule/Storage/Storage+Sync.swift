//
//  Storage+Sync.swift
//  RayonModule
//
//  What iCloud sync asks of the database: the changes still to send, the
//  CloudKit system fields of each record, and records from other devices,
//  merged by the time they were changed (the later one wins).
//

import Foundation
@preconcurrency import WCDBSwift

extension RayonStorage {
    /// Posted after a change here was queued for iCloud.
    static let didQueueChanges = Notification.Name("me.mizorewww.rayon.storage.didQueueChanges")
    /// Posted after records from another device were written.
    public static let didMergeRemoteChanges = Notification.Name("me.mizorewww.rayon.storage.didMergeRemoteChanges")

    /// The CloudKit record name of a record: "<id>:<table>".
    static func recordName(table: String, id: UUID) -> String {
        "\(id.uuidString):\(table)"
    }

    static func parse(recordName: String) -> (table: String, id: UUID)? {
        let parts = recordName.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[0]) else { return nil }
        return (parts[1], id)
    }

    static func recordType(named table: String) -> (any StoredRecord.Type)? {
        recordTypes.first { $0.tableName == table }
    }

    // MARK: Upload queue

    func pendingUploads() -> [UploadQueueEntry] {
        (try? db.getObjects(fromTable: UploadQueueEntry.tableName)) ?? []
    }

    /// Takes a change off the queue once iCloud has it, unless the record
    /// changed again since what was sent.
    func dequeue(table: String, id: UUID, sentModified: Date) {
        let entries: [UploadQueueEntry] = (try? db.getObjects(
            fromTable: UploadQueueEntry.tableName,
            where: UploadQueueEntry.Properties.tableName == table && UploadQueueEntry.Properties.objectId == id.uuidString
        )) ?? []
        for entry in entries where entry.modified.millisecondsSince1970 <= sentModified.millisecondsSince1970 {
            try? db.delete(
                fromTable: UploadQueueEntry.tableName,
                where: UploadQueueEntry.Properties.tableName == table && UploadQueueEntry.Properties.objectId == id.uuidString
            )
        }
    }

    /// Queues every record again, for an account that has none of them.
    func enqueueEverything() throws {
        try db.run(transaction: { handle in
            for type in Self.recordTypes {
                try self.enqueueAll(type, handle: handle)
            }
        })
        NotificationCenter.default.post(name: Self.didQueueChanges, object: self)
    }

    private func enqueueAll<T: StoredRecord>(_: T.Type, handle: Handle) throws {
        let rows: [T] = try handle.getObjects(fromTable: T.tableName)
        for row in rows {
            try enqueueUpload(T.self, id: row.id, modified: row.modified, handle: handle)
        }
    }

    /// The record to send for `recordName`, with its secrets; deleted ones
    /// too, so the deletion travels.
    func recordToSend(named recordName: String) -> (any StoredRecord)? {
        guard let (table, id) = Self.parse(recordName: recordName),
              let type = Self.recordType(named: table)
        else { return nil }
        func read<T: StoredRecord>(_: T.Type) -> (any StoredRecord)? {
            row(T.self, id: id).map(withSecrets)
        }
        return read(type)
    }

    // MARK: System fields

    func systemFields(for recordName: String) -> Data? {
        let row: SyncMetadata? = try? db.getObject(
            fromTable: SyncMetadata.tableName,
            where: SyncMetadata.Properties.recordName == recordName
        )
        return row?.systemFields
    }

    func setSystemFields(_ data: Data?, for recordName: String) {
        if let data {
            try? db.insertOrReplace([SyncMetadata(recordName: recordName, systemFields: data)], intoTable: SyncMetadata.tableName)
        } else {
            try? db.delete(fromTable: SyncMetadata.tableName, where: SyncMetadata.Properties.recordName == recordName)
        }
    }

    func removeAllSystemFields() {
        try? db.delete(fromTable: SyncMetadata.tableName)
    }

    /// Forgets what iCloud has and what is still to send it, for sync
    /// turned off: queued deletions no longer pin their tombstones, and
    /// turning sync on again sends everything.
    func forgetSyncState() {
        try? db.delete(fromTable: UploadQueueEntry.tableName)
        removeAllSystemFields()
        purgeTombstones()
    }

    // MARK: Changes from other devices

    enum MergeOutcome: Equatable {
        /// Nothing changed here.
        case unchanged
        /// The one here is newer: it goes out again.
        case keptLocal
        /// The other device's was written here.
        case tookRemote
    }

    /// Merges a record from another device: the later change wins, and a
    /// record taken from there keeps what belongs to this device.
    @discardableResult
    func mergeRemote<T: StoredRecord>(_ remote: T) throws -> MergeOutcome {
        let local = row(T.self, id: remote.id).map(withSecrets)
        switch RecordMerge.resolve(local: local, remote: remote) {
        case .same:
            // The same change, whose secrets this device could not read
            // (the keychain items stayed on the device a backup came from):
            // the other device's fill them in.
            guard let local, local.secretsUnread, !remote.removed, remote.secrets != T.Secrets() else { return .unchanged }
            let present = try writeSecrets(of: remote)
            try db.run(transaction: { handle in try self.notePresence(present, of: remote, handle: handle) })
            return .tookRemote
        case .keepLocal:
            guard let local else { return .unchanged }
            try db.run(transaction: { handle in
                try self.enqueueUpload(T.self, id: local.id, modified: local.modified, handle: handle)
            })
            NotificationCenter.default.post(name: Self.didQueueChanges, object: self)
            return .keptLocal
        case let .takeRemote(record):
            var record = record
            record.secretsUnread = false
            if record.removed { record.secrets = .init() }
            let present = try writeSecrets(of: record)
            try db.run(transaction: { handle in
                try handle.insertOrReplace([record], intoTable: T.tableName)
                try self.notePresence(present, of: record, handle: handle)
                // What came from there need not go back.
                try handle.delete(
                    fromTable: UploadQueueEntry.tableName,
                    where: UploadQueueEntry.Properties.tableName == T.tableName
                        && UploadQueueEntry.Properties.objectId == record.id.uuidString
                )
            })
            return .tookRemote
        }
    }

    /// A record gone from iCloud altogether (its zone reset, say): it goes
    /// here too, with its secrets and anything queued for it.
    func removeForSync(table: String, id: UUID) {
        guard let type = Self.recordType(named: table) else { return }
        func remove<T: StoredRecord>(_: T.Type) {
            try? db.run(transaction: { handle in
                try handle.delete(fromTable: T.tableName, where: Column(named: "id") == id.uuidString)
                try handle.delete(
                    fromTable: UploadQueueEntry.tableName,
                    where: UploadQueueEntry.Properties.tableName == T.tableName
                        && UploadQueueEntry.Properties.objectId == id.uuidString
                )
                try handle.delete(fromTable: SecretPresence.tableName, where: SecretPresence.Properties.account == "\(T.tableName).\(id.uuidString)")
            })
            try? secrets.remove("\(T.tableName).\(id.uuidString)")
        }
        remove(type)
        setSystemFields(nil, for: Self.recordName(table: table, id: id))
    }
}
