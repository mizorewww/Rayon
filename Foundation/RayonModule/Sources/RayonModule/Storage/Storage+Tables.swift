//
//  Storage+Tables.swift
//  RayonModule
//
//  The tables that are not the user's records: what this device knows of
//  servers' host keys, its recent connections, and the state of sync.
//

import Foundation
@preconcurrency import WCDBSwift

/// A server's host key, as known_hosts keeps it, by `[host]:port`.
struct KnownHostRecord: TableCodable, Equatable {
    static let tableName = "KnownHost"

    var name: String = ""
    var type: String = ""
    var key: Data = .init()
    var added: Date = .init()
    /// Saved by a release before 2.9, whose libssh2 preferred an ECDSA or
    /// RSA host key: the server's Ed25519 key, asked for first now, is
    /// then expected once rather than a sign of interception.
    var legacy: Bool = false

    enum CodingKeys: String, CodingTableKey {
        typealias Root = KnownHostRecord
        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(name, isPrimary: true)
            BindColumnConstraint(type, isNotNull: true)
            BindColumnConstraint(key, isNotNull: true)
            BindColumnConstraint(added, isNotNull: true)
            BindColumnConstraint(legacy, isNotNull: true, defaultTo: false)
        }

        case name
        case type
        case key
        case added
        case legacy
    }
}

/// A recent connection: a saved server, or a Quick Connect command.
struct RecentConnectionRecord: TableCodable, Equatable {
    static let tableName = "RecentConnection"

    var id: String = ""
    var machine: UUID?
    var command: SSHCommandReader?
    var position: Int = 0

    enum CodingKeys: String, CodingTableKey {
        typealias Root = RecentConnectionRecord
        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(position, isNotNull: true)
        }

        case id
        case machine
        case command
        case position
    }
}

extension SSHCommandReader: ColumnJSONCodable {}

/// A record changed here that iCloud has not received yet. One entry per
/// record: a newer change replaces the entry.
struct UploadQueueEntry: TableCodable, Equatable {
    static let tableName = "UploadQueue"

    var tableName: String = ""
    var objectId: UUID = .init()
    var modified: Date = .init()

    enum CodingKeys: String, CodingTableKey {
        typealias Root = UploadQueueEntry
        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(tableName, isNotNull: true)
            BindColumnConstraint(objectId, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindIndex(tableName, objectId, namedWith: "_tableNameObjectIdIndex", isUnique: true)
        }

        case tableName
        case objectId
        case modified
    }
}

/// The CloudKit system fields of a record as last seen, so the next save of
/// it is not taken for a conflict.
struct SyncMetadata: TableCodable, Equatable {
    static let tableName = "SyncMetadata"

    var recordName: String = ""
    var systemFields: Data = .init()

    enum CodingKeys: String, CodingTableKey {
        typealias Root = SyncMetadata
        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(recordName, isPrimary: true)
            BindColumnConstraint(systemFields, isNotNull: true)
        }

        case recordName
        case systemFields
    }
}

/// A record whose secrets are in the keychain. When the keychain has no
/// item for it, the item is missing (left on the device a backup came
/// from), not empty, and the record's secrets count as unread.
struct SecretPresence: TableCodable, Equatable {
    static let tableName = "SecretPresence"

    var account: String = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = SecretPresence
        static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(account, isPrimary: true)
        }

        case account
    }
}

extension RayonStorage {
    func enqueueUpload<T: StoredRecord>(_: T.Type, id: UUID, modified: Date, handle: Handle) throws {
        let entry = UploadQueueEntry(tableName: T.tableName, objectId: id, modified: modified)
        try handle.insertOrReplace([entry], intoTable: UploadQueueEntry.tableName)
    }
}

// MARK: - Known hosts

extension RayonStorage {
    func knownHost(named name: String) -> KnownHostRecord? {
        try? db.getObject(fromTable: KnownHostRecord.tableName, where: KnownHostRecord.Properties.name == name)
    }

    func saveKnownHost(_ record: KnownHostRecord) throws {
        try db.insertOrReplace([record], intoTable: KnownHostRecord.tableName)
    }

    func removeKnownHost(named name: String) throws {
        try db.delete(fromTable: KnownHostRecord.tableName, where: KnownHostRecord.Properties.name == name)
    }

    func removeAllKnownHosts() throws {
        try db.delete(fromTable: KnownHostRecord.tableName)
    }

    var knownHostCount: Int {
        ((try? db.getObjects(fromTable: KnownHostRecord.tableName)) as [KnownHostRecord]?)?.count ?? 0
    }
}

// MARK: - Recent connections

extension RayonStorage {
    func recentConnections() -> [RecentConnectionRecord] {
        (try? db.getObjects(
            fromTable: RecentConnectionRecord.tableName,
            orderBy: [RecentConnectionRecord.Properties.position.order(.ascending)]
        )) ?? []
    }

    /// Replaces the list.
    func saveRecentConnections(_ records: [RecentConnectionRecord]) throws {
        try db.run(transaction: { handle in
            try handle.delete(fromTable: RecentConnectionRecord.tableName)
            try handle.insertOrReplace(records, intoTable: RecentConnectionRecord.tableName)
        })
    }
}
