//
//  UnreadSecretsTests.swift
//  RayonModuleTests
//
//  A record whose secrets the keychain does not give (locked before the
//  first unlock, or its items left on the device a backup came from) is
//  saved without touching them, and is not sent to iCloud with them empty.
//

import CloudKit
@testable import RayonModule
import XCTest

final class UnreadSecretsTests: XCTestCase {
    private var test: TestStorage!
    private var storage: RayonStorage!

    override func setUpWithError() throws {
        test = try TestStorage()
        storage = test.storage
    }

    override func tearDown() {
        if storage !== test.storage { storage.close() }
        test = nil
    }

    private var account: (RDMachine) -> String { { "\(RDMachine.tableName).\($0.id.uuidString)" } }

    /// The same database, through a keychain that refuses the item.
    private func reopen(refusing accounts: Set<String>) throws {
        if storage !== test.storage { storage.close() }
        var secrets = test.secrets
        secrets.refusedAccounts = accounts
        storage = try RayonStorage(databaseURL: test.storage.databaseURL, secrets: secrets)
    }

    private func savedServer() throws -> RDMachine {
        var server = RDMachine(remoteAddress: "10.0.0.1", remotePort: "22", name: "web")
        server.vncPassword = "vnc-secret"
        server.cloudflareServiceTokenSecret = "token"
        let saved = try test.storage.save(server)
        try test.storage.db.delete(fromTable: UploadQueueEntry.tableName)
        return saved
    }

    func testAnUnreadableSecretSurvivesAnUnrelatedSave() async throws {
        let server = try savedServer()
        try reopen(refusing: [account(server)])

        var read = try XCTUnwrap(storage.record(RDMachine.self, id: server.id))
        XCTAssertTrue(read.secretsUnread)
        XCTAssertEqual(read.vncPassword, "")

        read.name = "renamed"
        let saved = try storage.save(read)
        XCTAssertTrue(saved.secretsUnread)
        XCTAssertEqual(try test.secrets.value(RDMachine.Secrets.self, for: account(server))?.vncPassword, "vnc-secret")

        // The change is queued, but not sent while its secrets are unknown.
        XCTAssertEqual(storage.pendingUploads().map(\.objectId), [server.id])
        let sync = CloudSync(storage: storage)
        await sync.apply(CloudSyncPreferences(isOn: true))
        let id = CloudRecordCoding.recordID(table: RDMachine.tableName, id: server.id)
        let refused = await sync.ckRecord(for: id)
        XCTAssertNil(refused)

        // Once the keychain gives them, they are there and go out.
        try reopen(refusing: [])
        let unlocked = try XCTUnwrap(storage.record(RDMachine.self, id: server.id))
        XCTAssertFalse(unlocked.secretsUnread)
        XCTAssertEqual(unlocked.name, "renamed")
        XCTAssertEqual(unlocked.vncPassword, "vnc-secret")
        let unlockedSync = CloudSync(storage: storage)
        await unlockedSync.apply(CloudSyncPreferences(isOn: true))
        let sent = await unlockedSync.ckRecord(for: id)
        XCTAssertNotNil(sent?.encryptedValues[CloudRecordCoding.Field.secrets])
    }

    /// Passwords typed in while the old ones could not be read are saved.
    func testNewSecretsTypedInAreWritten() throws {
        let server = try savedServer()
        try reopen(refusing: [account(server)])
        var read = try XCTUnwrap(storage.record(RDMachine.self, id: server.id))
        read.vncPassword = "typed"
        XCTAssertThrowsError(try storage.save(read), "the keychain still refuses")
        try reopen(refusing: [])
        XCTAssertEqual(storage.record(RDMachine.self, id: server.id)?.vncPassword, "vnc-secret")

        try reopen(refusing: [])
        read.vncPassword = "typed"
        XCTAssertEqual(try storage.save(read).vncPassword, "typed")
        XCTAssertEqual(storage.record(RDMachine.self, id: server.id)?.vncPassword, "typed")
    }

    /// A backup restored on a new device: the database came along, the
    /// keychain items did not. The secrets are missing, not empty.
    func testAMissingItemIsUnreadAndFilledFromAnotherDevice() throws {
        let server = try savedServer()
        try test.secrets.remove(account(server))

        var read = try XCTUnwrap(storage.record(RDMachine.self, id: server.id))
        XCTAssertTrue(read.secretsUnread)
        read.comment = "edited"
        read = try storage.save(read)
        XCTAssertTrue(read.secretsUnread)

        // Another device has the same change, with the secrets.
        var remote = server
        remote.comment = "edited"
        remote.modified = read.modified
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        let filled = try XCTUnwrap(storage.record(RDMachine.self, id: server.id))
        XCTAssertFalse(filled.secretsUnread)
        XCTAssertEqual(filled.vncPassword, "vnc-secret")
        XCTAssertEqual(filled.cloudflareServiceTokenSecret, "token")
    }

    /// A record with no secrets at all is not taken for one whose secrets
    /// are missing.
    func testARecordWithoutSecretsIsRead() throws {
        let plain = try storage.save(RDMachine(remoteAddress: "10.0.0.2", remotePort: "22", name: "plain"))
        XCTAssertEqual(storage.record(RDMachine.self, id: plain.id)?.secretsUnread, false)
        let identity = try storage.save(RDIdentity(username: "root", password: "pw"))
        XCTAssertEqual(storage.record(RDIdentity.self, id: identity.id)?.secretsUnread, false)
        var cleared = identity
        cleared.password = ""
        try storage.save(cleared)
        XCTAssertEqual(storage.record(RDIdentity.self, id: identity.id)?.secretsUnread, false)
    }
}
