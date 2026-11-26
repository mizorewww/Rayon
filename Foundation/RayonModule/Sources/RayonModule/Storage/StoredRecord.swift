//
//  StoredRecord.swift
//  RayonModule
//
//  What a table of the user's data (servers, identities, folders, snippets,
//  port forwards) has in common: a UUID, the time of its last change, and a
//  deletion mark, so that a deletion reaches the other devices instead of
//  being undone by them. Secrets are part of the record in memory and in
//  what syncs, but are kept in the keychain, never in the database.
//

import Foundation
@preconcurrency import WCDBSwift

public protocol StoredRecord: TableCodable, Identifiable, Equatable, Sendable where ID == UUID {
    associatedtype Secrets: RecordSecrets = NoSecrets

    static var tableName: String { get }

    var id: UUID { get }
    var modified: Date { get set }
    var removed: Bool { get set }
    var secrets: Secrets { get set }
    /// The keychain did not give the secrets when the record was read
    /// (locked before the first unlock, or the items stayed on the device a
    /// backup came from): `secrets` says nothing about them, and nothing
    /// may write or send them.
    var secretsUnread: Bool { get set }

    /// The record without what belongs to this device alone (when a server
    /// was last used, say), which neither syncs nor counts as a change.
    var syncedContent: Self { get }

    /// The record from another device, with this device's own fields kept
    /// from `local`.
    func keepingLocalState(of local: Self) -> Self
}

public extension StoredRecord {
    var syncedContent: Self { self }
    func keepingLocalState(of _: Self) -> Self { self }
}

public extension StoredRecord where Secrets == NoSecrets {
    var secretsUnread: Bool {
        get { false }
        set {}
    }
}

/// The secrets of a record, kept in the keychain under the record's id.
public protocol RecordSecrets: Codable, Equatable, Sendable {
    init()
}

public struct NoSecrets: RecordSecrets {
    public init() {}
}

extension StoredRecord {
    /// Whether the two differ in anything that syncs.
    func differsInSyncedContent(from other: Self) -> Bool {
        var lhs = syncedContent
        var rhs = other.syncedContent
        lhs.modified = .distantPast
        rhs.modified = .distantPast
        lhs.secretsUnread = false
        rhs.secretsUnread = false
        return lhs != rhs
    }

    /// What syncs of the record, as the same bytes on every device: for
    /// telling versions apart by their content alone.
    var syncedContentData: Data {
        var content = syncedContent
        content.modified = Date(timeIntervalSinceReferenceDate: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return (try? encoder.encode(RecordPayload(content))) ?? Data()
    }

    var secretAccount: String { "\(Self.tableName).\(id.uuidString)" }
}

/// What travels for a record: the row and its secrets. CloudKit keeps it in
/// an encrypted field.
public struct RecordPayload<Record: StoredRecord>: Codable {
    var record: Record
    var secrets: Record.Secrets

    init(_ record: Record) {
        self.record = record
        secrets = record.secrets
    }

    var resolved: Record {
        var record = record
        record.secrets = secrets
        return record
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Record {
        try decoder.decode(Self.self, from: data).resolved
    }
}

/// How a record from another device and the one here are merged: the one
/// changed last wins. Two different versions changed at the same time (first
/// records, stamped as old on each device) are told apart by their content,
/// so every device keeps the same one.
enum RecordMerge<Record: StoredRecord>: Equatable {
    /// Nothing to do: they are the same change, or the secrets here could
    /// not be read to tell.
    case same
    /// The one here is newer and goes out again.
    case keepLocal
    /// The other device's is written here.
    case takeRemote(Record)

    static func resolve(local: Record?, remote: Record) -> Self {
        guard let local else { return .takeRemote(remote) }
        let here = local.modified.millisecondsSince1970
        let there = remote.modified.millisecondsSince1970
        if here == there {
            guard !local.secretsUnread, local.differsInSyncedContent(from: remote) else { return .same }
            return remote.syncedContentData.lexicographicallyPrecedes(local.syncedContentData)
                ? .keepLocal : .takeRemote(remote.keepingLocalState(of: local))
        }
        if here > there { return .keepLocal }
        return .takeRemote(remote.keepingLocalState(of: local))
    }
}
