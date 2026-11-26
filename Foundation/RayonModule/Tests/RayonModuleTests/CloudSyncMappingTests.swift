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
        let ck = try CloudRecordCoding.ckRecord(for: identity, systemFields: nil)
        XCTAssertEqual(ck.recordType, RDIdentity.tableName)
        XCTAssertEqual(ck.recordID.zoneID, CloudRecordCoding.zoneID)
        XCTAssertNotNil(ck.encryptedValues[CloudRecordCoding.Field.secrets])
        XCTAssertNil(ck[CloudRecordCoding.Field.secrets])
        let back = try XCTUnwrap(CloudRecordCoding.decode(ck) as? RDIdentity)
        XCTAssertEqual(back, identity.syncedContent)

        var machine = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        machine.lastBanner = "Welcome"
        let sent = try XCTUnwrap(CloudRecordCoding.decode(
            CloudRecordCoding.ckRecord(for: machine, systemFields: nil)
        ) as? RDMachine)
        XCTAssertEqual(sent.lastBanner, "")
    }

    /// A large record is still encrypted, never in an asset; one too large
    /// for a CloudKit record is not sent. A record an earlier build sent in
    /// an asset is still read, and the asset dropped when it is sent again.
    func testLargeRecordsStayEncrypted() throws {
        var snippet = RDSnippet(name: "big", group: "", code: String(repeating: "x", count: 64 * 1024), comment: "")
        snippet.modified = Date(timeIntervalSince1970: 1_700_000_000)
        let ck = try CloudRecordCoding.ckRecord(for: snippet, systemFields: nil)
        XCTAssertNotNil(ck.encryptedValues[CloudRecordCoding.Field.record])
        XCTAssertNil(ck[CloudRecordCoding.Field.recordAsset])
        XCTAssertEqual(try CloudRecordCoding.decode(ck) as? RDSnippet, snippet)

        var huge = snippet
        huge.code = String(repeating: "x", count: 1024 * 1024)
        XCTAssertThrowsError(try CloudRecordCoding.ckRecord(for: huge, systemFields: nil))

        let file = test.directory.appendingPathComponent("asset")
        var older = snippet
        older.name = "old"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(older).write(to: file)
        let old = CKRecord(recordType: RDSnippet.tableName, recordID: ck.recordID)
        old[CloudRecordCoding.Field.recordAsset] = CKAsset(fileURL: file)
        XCTAssertEqual((try CloudRecordCoding.decode(old) as? RDSnippet)?.name, "old")
        let resent = try CloudRecordCoding.ckRecord(for: snippet, systemFields: CloudRecordCoding.encode(systemFields: old))
        XCTAssertNil(resent[CloudRecordCoding.Field.recordAsset])
    }

    func testSystemFieldsAreReused() throws {
        let machine = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        let first = try CloudRecordCoding.ckRecord(for: machine, systemFields: nil)
        let fields = CloudRecordCoding.encode(systemFields: first)
        let again = try CloudRecordCoding.ckRecord(for: machine, systemFields: fields)
        XCTAssertEqual(again.recordID, first.recordID)
        // Fields of another record are not taken.
        let other = try CloudRecordCoding.ckRecord(
            for: RDMachine(remoteAddress: "b", remotePort: "22", name: "b"),
            systemFields: fields)
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

    /// Saves keep queueing while sync is off; turning it off (or starting
    /// with it off) drops the queue, so deletions do not pin their
    /// tombstones forever.
    func testSyncOffForgetsTheQueueAndLetsTombstonesGo() async throws {
        let machine = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        try storage.delete(RDMachine.self, ids: [machine.id])
        storage.setSystemFields(Data([1]), for: RayonStorage.recordName(table: RDMachine.tableName, id: machine.id))
        let stateURL = test.directory.appendingPathComponent("sync-state.json")
        try Data("{}".utf8).write(to: stateURL)

        await CloudSync(storage: storage).apply(CloudSyncPreferences(isOn: false))

        XCTAssertTrue(storage.pendingUploads().isEmpty)
        XCTAssertNil(storage.systemFields(for: RayonStorage.recordName(table: RDMachine.tableName, id: machine.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path), "turning sync on again starts as a sign-in")
        storage.purgeTombstones(now: Date().addingTimeInterval(RayonStorage.tombstoneLifetime + 1))
        XCTAssertNil(storage.row(RDMachine.self, id: machine.id))
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

    /// While a kind is left out, the engine drops what it fetches of it and
    /// moves on; letting it in again fetches everything again, or the other
    /// devices' changes made in between would never arrive.
    func testLettingAKindInAgainFetchesEverything() {
        let all = CloudSyncPreferences(isOn: true).syncedTables
        XCTAssertEqual(all, Set(RayonStorage.recordTypes.map { $0.tableName }))
        let withoutSnippets = CloudSyncPreferences(isOn: true, snippets: false).syncedTables
        XCTAssertFalse(withoutSnippets.contains(RDSnippet.tableName))

        XCTAssertTrue(CloudSync.needsRefetch(covered: withoutSnippets, syncing: all))
        XCTAssertFalse(CloudSync.needsRefetch(covered: all, syncing: withoutSnippets), "leaving a kind out needs nothing")
        XCTAssertFalse(CloudSync.needsRefetch(covered: all, syncing: all))
        XCTAssertFalse(CloudSync.needsRefetch(covered: nil, syncing: all), "a first start fetches everything anyway")
    }
}
