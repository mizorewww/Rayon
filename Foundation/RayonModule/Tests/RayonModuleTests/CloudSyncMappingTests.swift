//
//  CloudSyncMappingTests.swift
//  RayonModuleTests
//
//  What iCloud sync does with records, without CloudKit itself: the
//  mapping to and from CKRecord, merging other devices' records, and what
//  the user's choices let through.
//

import CloudKit
import os
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
    /// Sync off forgets what iCloud has, but not a deletion still to send:
    /// its tombstone stays, so the server does not come back from iCloud
    /// when sync is turned on again.
    func testSyncOffKeepsDeletionsToSend() async throws {
        let machine = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        try storage.delete(RDMachine.self, ids: [machine.id])
        storage.setSystemFields(Data([1]), for: RayonStorage.recordName(table: RDMachine.tableName, id: machine.id))
        let stateURL = test.directory.appendingPathComponent("sync-state.json")
        try Data("{}".utf8).write(to: stateURL)

        await CloudSync(storage: storage).apply(CloudSyncPreferences(isOn: false))

        XCTAssertEqual(storage.pendingUploads().map(\.objectId), [machine.id])
        XCTAssertNil(storage.systemFields(for: RayonStorage.recordName(table: RDMachine.tableName, id: machine.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path), "turning sync on again starts as a sign-in")
        storage.purgeTombstones(now: Date().addingTimeInterval(RayonStorage.tombstoneLifetime + 1))
        XCTAssertEqual(storage.row(RDMachine.self, id: machine.id)?.removed, true)

        // The same server from iCloud, as it was before the deletion, stays deleted.
        var remote = machine
        remote.removed = false
        XCTAssertNotEqual(try storage.mergeRemote(remote), .tookRemote)
        XCTAssertEqual(storage.row(RDMachine.self, id: machine.id)?.removed, true)
    }

    /// A change from another device that cannot be merged now (the
    /// keychain refuses its secrets) keeps no system fields, or the version
    /// here would be sent over it, and is merged again later.
    func testAChangeThatFailsToMergeIsRetried() async throws {
        var server = RDMachine(remoteAddress: "10.0.0.1", remotePort: "22", name: "web")
        server.vncPassword = "vnc"
        server = try storage.save(server)
        var refusing = test.secrets
        refusing.refusedAccounts = [server.secretAccount]
        let locked = try RayonStorage(databaseURL: storage.databaseURL, secrets: refusing)
        defer { locked.close() }
        var remote = server
        remote.name = "renamed there"
        remote.vncPassword = "changed"
        remote.modified = server.modified.addingTimeInterval(60)
        let ck = try CloudRecordCoding.ckRecord(for: remote, systemFields: nil)
        let name = ck.recordID.recordName

        let sync = CloudSync(storage: locked)
        await sync.apply(CloudSyncPreferences(isOn: true))
        let took = await sync.receive(ck)
        XCTAssertFalse(took)
        XCTAssertNil(storage.systemFields(for: name))
        let failed = await sync.failedMerges
        XCTAssertEqual(failed, [name])
        // It is still to merge after a relaunch.
        let relaunched = await CloudSync(storage: locked).failedMerges
        XCTAssertEqual(relaunched, [name])

        // Unlocked, the retry takes it.
        let unlocked = CloudSync(storage: storage)
        await unlocked.apply(CloudSyncPreferences(isOn: true))
        let tookNow = await unlocked.receive(ck)
        XCTAssertTrue(tookNow)
        XCTAssertNotNil(storage.systemFields(for: name))
        let left = await unlocked.failedMerges
        XCTAssertEqual(left, [])
        XCTAssertEqual(storage.record(RDMachine.self, id: server.id)?.name, "renamed there")
        XCTAssertEqual(storage.record(RDMachine.self, id: server.id)?.vncPassword, "changed")
    }

    /// CloudKit fetches at most 400 records per request: a longer retry
    /// list used to go in one request, which fails as a whole.
    func testRetriedMergesAreFetchedAtMost400AtATime() async throws {
        let names = Set((0 ..< 1000).map { "RDMachine.\($0)" })
        let retryURL = storage.databaseURL.deletingLastPathComponent().appendingPathComponent("sync-retry.json")
        try JSONEncoder().encode(names).write(to: retryURL)
        let sync = CloudSync(storage: storage)
        let batches = OSAllocatedUnfairLock<[Int]>(initialState: [])
        await sync.retryFailedMerges { ids in
            batches.withLock { $0.append(ids.count) }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, .failure(CKError(.unknownItem))) })
        }
        XCTAssertEqual(batches.withLock { $0 }.reduce(0, +), 1000)
        XCTAssertLessThanOrEqual(batches.withLock { $0 }.max() ?? 0, 400, "\(batches.withLock { $0 })")
        let left = await sync.failedMerges
        XCTAssertEqual(left, [], "every record was fetched")
    }

    /// A change of a kind the user stopped syncing is not sent, even when
    /// the engine was told of it before: identities left out keep their
    /// secrets off iCloud. It stays queued, for when they sync again.
    func testAKindLeftOutIsNotSent() async throws {
        let identity = try storage.save(RDIdentity(username: "root", password: "pw", privateKey: "KEY"))
        let id = CloudRecordCoding.recordID(table: RDIdentity.tableName, id: identity.id)
        let sync = CloudSync(storage: storage)
        await sync.apply(CloudSyncPreferences(isOn: true))
        let sent = await sync.ckRecord(for: id)
        XCTAssertNotNil(sent)

        await sync.apply(CloudSyncPreferences(isOn: true, identities: false))
        let excluded = await sync.ckRecord(for: id)
        XCTAssertNil(excluded)
        XCTAssertEqual(storage.pendingUploads().map(\.objectId), [identity.id])
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
