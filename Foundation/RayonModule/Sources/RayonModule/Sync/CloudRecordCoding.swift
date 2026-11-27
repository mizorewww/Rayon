//
//  CloudRecordCoding.swift
//  RayonModule
//
//  A record as a CloudKit record, after FlowDown's sync: record type = the
//  table, record name = "<id>:<table>". The record (without its secrets)
//  is JSON in an encrypted field, and the secrets are in an encrypted field
//  of their own. Nothing goes in a CKAsset: an asset is not encrypted, so a
//  record too large for one CloudKit record is not sent. The CloudKit system
//  fields kept from the last exchange make a save an update, not a conflict.
//

import CloudKit
import Foundation

enum CloudRecordCoding {
    static let zoneID = CKRecordZone.ID(zoneName: "Rayon", ownerName: CKCurrentUserDefaultName)

    enum Field {
        static let record = "record"
        static let secrets = "secrets"
        static let modified = "modified"
    }

    /// A CloudKit record holds about 1 MB; a larger record is not sent.
    static let inlineLimit = 768 * 1024

    struct TooLarge: Error {}

    static func recordID(table: String, id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: RayonStorage.recordName(table: table, id: id), zoneID: zoneID)
    }

    static func encode(systemFields record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decode(systemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
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

    /// The CloudKit record for `record`, on top of the system fields last
    /// seen for it; `TooLarge` when it cannot fit in one.
    static func ckRecord<T: StoredRecord>(for record: T, systemFields: Data?) throws -> CKRecord {
        let id = recordID(table: T.tableName, id: record.id)
        let ck = systemFields.flatMap(decode(systemFields:)).flatMap { $0.recordID == id ? $0 : nil }
            ?? CKRecord(recordType: T.tableName, recordID: id)
        // What belongs to this device stays here.
        var plain = record.syncedContent
        plain.secrets = .init()
        let data = try encoder.encode(plain)
        guard data.count <= inlineLimit else { throw TooLarge() }
        ck.encryptedValues[Field.record] = data
        if T.Secrets.self != NoSecrets.self {
            ck.encryptedValues[Field.secrets] = try encoder.encode(record.secrets)
        }
        ck[Field.modified] = record.modified.millisecondsSince1970
        return ck
    }

    /// The record in a CloudKit record from another device.
    static func decode(_ ck: CKRecord) throws -> any StoredRecord {
        guard let (table, _) = RayonStorage.parse(recordName: ck.recordID.recordName),
              let type = RayonStorage.recordType(named: table)
        else { throw CocoaError(.coderInvalidValue) }
        return try decode(ck, as: type)
    }

    private static func decode<T: StoredRecord>(_ ck: CKRecord, as _: T.Type) throws -> T {
        guard let data = ck.encryptedValues[Field.record] as? Data else { throw CocoaError(.coderValueNotFound) }
        var record = try decoder.decode(T.self, from: data)
        if T.Secrets.self != NoSecrets.self, let secrets = ck.encryptedValues[Field.secrets] as? Data {
            record.secrets = try decoder.decode(T.Secrets.self, from: secrets)
        }
        return record
    }
}
