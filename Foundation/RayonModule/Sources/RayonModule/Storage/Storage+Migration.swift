//
//  Storage+Migration.swift
//  RayonModule
//
//  The schema is versioned with `PRAGMA user_version`; each migration moves
//  it up exactly one version. A new version adds a migration here and the
//  tables it changes, never edits an older one.
//

import Foundation
@preconcurrency import WCDBSwift

enum DBVersion: Int, CaseIterable {
    case empty = 0
    case v1 = 1
    case v2 = 2
    case v3 = 3
}

struct DBMigration: Sendable {
    let from: DBVersion
    let to: DBVersion
    let migrate: @Sendable (Handle) throws -> Void

    static let all: [DBMigration] = [
        DBMigration(from: .empty, to: .v1) { db in
            try db.create(table: RDFolder.tableName, of: RDFolder.self)
            try db.create(table: RDIdentity.tableName, of: RDIdentity.self)
            try db.create(table: RDMachine.tableName, of: RDMachine.self)
            try db.create(table: RDSnippet.tableName, of: RDSnippet.self)
            try db.create(table: RDPortForward.tableName, of: RDPortForward.self)
            try db.create(table: KnownHostRecord.tableName, of: KnownHostRecord.self)
            try db.create(table: RecentConnectionRecord.tableName, of: RecentConnectionRecord.self)
            try db.create(table: UploadQueueEntry.tableName, of: UploadQueueEntry.self)
            try db.create(table: SyncMetadata.tableName, of: SyncMetadata.self)
        },
        DBMigration(from: .v1, to: .v2) { db in
            try db.create(table: RDTerminalSettings.tableName, of: RDTerminalSettings.self)
        },
        DBMigration(from: .v2, to: .v3) { db in
            try db.create(table: SecretPresence.tableName, of: SecretPresence.self)
        },
    ]

    static func migrate(_ db: Database) throws {
        precondition(all.allSatisfy { $0.to.rawValue == $0.from.rawValue + 1 }, "a migration crosses versions")
        var version = try currentVersion(of: db)
        while let step = all.first(where: { $0.from == version }) {
            try db.run(transaction: { handle in
                try step.migrate(handle)
                try handle.exec(StatementPragma().pragma(.userVersion).to(step.to.rawValue))
            })
            version = step.to
        }
    }

    static func currentVersion(of db: Database) throws -> DBVersion {
        let value = try db.getValue(from: StatementPragma().pragma(.userVersion))
        let raw = value?.intValue ?? 0
        guard let version = DBVersion(rawValue: raw) else { throw NewerSchema(version: raw) }
        return version
    }

    /// The database was last written by a newer Rayon.
    struct NewerSchema: LocalizedError {
        let version: Int
        var errorDescription: String? {
            "The database is from a newer version of Rayon (schema \(version))."
        }
    }
}
