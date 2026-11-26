//
//  CloudSyncMappingTests.swift
//  RayonModuleTests
//
//  What iCloud sync does with records, without CloudKit itself: the
//  mapping to and from CKRecord, merging other devices' records, and what
//  the user's choices let through.
//

import CloudKit
@testable import RayonModule
import XCTest

final class CloudSyncMappingTests: XCTestCase {
    private var test: TestStorage!
    private var storage: RayonStorage { test.storage }
    private var assets: URL { test.directory.appendingPathComponent("assets") }

    override func setUpWithError() throws {
        test = try TestStorage()
    }

    override func tearDown() {
        test = nil
    }

    func testRecordNamesRoundTrip() {
        let id = UUID()
        let name = RayonStorage.recordName(table: RDMachine.tableName, id: id)
        XCTAssertEqual(RayonStorage.parse(recordName: name)?.id, id)
        XCTAssertEqual(RayonStorage.parse(recordName: name)?.table, RDMachine.tableName)
        XCTAssertNil(RayonStorage.parse(recordName: "nonsense"))
    }

    func testSecretsTravelEncryptedAndLocalStateStaysHere() throws {
        var identity = RDIdentity(username: "root", password: "pw")
        identity.modified = Date(timeIntervalSince1970: 1_700_000_000)
        let ck = try CloudRecordCoding.ckRecord(for: identity, systemFields: nil, assetDirectory: assets)
        XCTAssertEqual(ck.recordType, RDIdentity.tableName)
        XCTAssertEqual(ck.recordID.zoneID, CloudRecordCoding.zoneID)
        XCTAssertNotNil(ck.encryptedValues[CloudRecordCoding.Field.secrets])
        XCTAssertNil(ck[CloudRecordCoding.Field.secrets])
        let back = try XCTUnwrap(CloudRecordCoding.decode(ck) as? RDIdentity)
        XCTAssertEqual(back, identity.syncedContent)

        var machine = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        machine.lastBanner = "Welcome"
        let sent = try XCTUnwrap(CloudRecordCoding.decode(
            CloudRecordCoding.ckRecord(for: machine, systemFields: nil, assetDirectory: assets)
        ) as? RDMachine)
        XCTAssertEqual(sent.lastBanner, "")
    }

    func testLargeRecordsGoInAnAsset() throws {
        var snippet = RDSnippet(name: "big", group: "", code: String(repeating: "x", count: 64 * 1024), comment: "")
        snippet.modified = Date(timeIntervalSince1970: 1_700_000_000)
        let ck = try CloudRecordCoding.ckRecord(for: snippet, systemFields: nil, assetDirectory: assets)
        XCTAssertNil(ck.encryptedValues[CloudRecordCoding.Field.record])
        XCTAssertNotNil(ck[CloudRecordCoding.Field.recordAsset] as? CKAsset)
        XCTAssertEqual(try CloudRecordCoding.decode(ck) as? RDSnippet, snippet)
    }

    func testSystemFieldsAreReused() throws {
        let machine = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        let first = try CloudRecordCoding.ckRecord(for: machine, systemFields: nil, assetDirectory: assets)
        let fields = CloudRecordCoding.encode(systemFields: first)
        let again = try CloudRecordCoding.ckRecord(for: machine, systemFields: fields, assetDirectory: assets)
        XCTAssertEqual(again.recordID, first.recordID)
        // Fields of another record are not taken.
        let other = try CloudRecordCoding.ckRecord(
            for: RDMachine(remoteAddress: "b", remotePort: "22", name: "b"),
            systemFields: fields,
            assetDirectory: assets
        )
        XCTAssertNotEqual(other.recordID, first.recordID)
    }

    func testAnOlderRemoteChangeIsSentBackOver() throws {
        let local = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "here"))
        try storage.db.delete(fromTable: UploadQueueEntry.tableName)
        var remote = local
        remote.name = "there"
        remote.modified = local.modified.addingTimeInterval(-60)
        XCTAssertEqual(try storage.mergeRemote(remote), .keptLocal)
        XCTAssertEqual(storage.record(RDMachine.self, id: local.id)?.name, "here")
        XCTAssertEqual(storage.pendingUploads().map(\.objectId), [local.id])
    }

    func testANewerRemoteChangeIsTakenWithItsSecretsAndNotSentBack() throws {
        let local = try storage.save(RDIdentity(username: "root", password: "old"))
        var remote = local
        remote.password = "new"
        remote.modified = local.modified.addingTimeInterval(60)
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        XCTAssertEqual(storage.record(RDIdentity.self, id: local.id)?.password, "new")
        XCTAssertTrue(storage.pendingUploads().isEmpty)
        XCTAssertEqual(try storage.mergeRemote(remote), .unchanged)
    }

    func testARemoteDeletionForgetsTheSecrets() throws {
        let local = try storage.save(RDIdentity(username: "root", password: "pw"))
        var remote = local
        remote.removed = true
        remote.modified = local.modified.addingTimeInterval(60)
        try storage.mergeRemote(remote)
        XCTAssertNil(storage.record(RDIdentity.self, id: local.id))
        XCTAssertNil(try test.secrets.data(for: local.secretAccount))
    }

    func testOnlyQueuedChangesAreSentAndOnlyOnce() throws {
        let machine = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        XCTAssertNotNil(storage.recordToSend(named: RayonStorage.recordName(table: RDMachine.tableName, id: machine.id)))
        storage.dequeue(table: RDMachine.tableName, id: machine.id, sentModified: machine.modified.addingTimeInterval(-1))
        XCTAssertEqual(storage.pendingUploads().count, 1, "a later change is still to send")
        storage.dequeue(table: RDMachine.tableName, id: machine.id, sentModified: machine.modified)
        XCTAssertTrue(storage.pendingUploads().isEmpty)
        try storage.enqueueEverything()
        XCTAssertEqual(storage.pendingUploads().count, 1)
    }

    func testTheScopeDecidesWhatSyncs() {
        var preferences = CloudSyncPreferences(isOn: true, identities: false)
        XCTAssertTrue(preferences.syncs(table: RDMachine.tableName))
        XCTAssertTrue(preferences.syncs(table: RDFolder.tableName))
        XCTAssertFalse(preferences.syncs(table: RDIdentity.tableName))
        XCTAssertFalse(preferences.syncs(table: KnownHostRecord.tableName))
        preferences.isOn = false
        XCTAssertFalse(preferences.syncs(table: RDMachine.tableName))

        let defaults = UserDefaults(suiteName: "rayon-tests-\(UUID().uuidString)")!
        XCTAssertEqual(CloudSyncPreferences(defaults: defaults), CloudSyncPreferences())
        preferences.save(to: defaults)
        XCTAssertEqual(CloudSyncPreferences(defaults: defaults), preferences)
    }
}
