@testable import RayonModule
import XCTest

/// What the previous releases stored comes into the database.
///
/// Fixtures/Legacy holds UserDefaults values written by the releases' own
/// code (their AES engines and record types, compiled from the v2.4, v2.6.2
/// and v2.8 tags) under the master key below:
/// - v2.4.plist: AES-CBC; a server's SFTP path in its attachment.
/// - v2.6.2.plist: "RGCM1"; transport and Cloudflare token in the attachment.
/// - v2.8.plist: a 2.8 install upgraded from 2.4, whose groups are each in
///   the format of the release that last changed them: servers and folders
///   "RGCM2", identities and forwards "RGCM1", snippets AES-CBC.
final class LegacyStoreImportTests: XCTestCase {
    private var directory: URL!
    private var secrets: SecretStore!
    private var storage: RayonStorage!
    private var defaults: UserDefaults!
    private let suite = "me.mizorewww.rayon.tests.legacy.\(UUID().uuidString)"
    private let master = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"

    private let identityID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let serverID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let jumpID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let snippetID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private let forwardID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        secrets = SecretStore(service: "me.mizorewww.rayon.tests.\(UUID().uuidString)")
        storage = try RayonStorage(databaseURL: directory.appendingPathComponent("database.db"), secrets: secrets)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        storage.close()
        try? secrets.removeAll()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    /// The values of a fixture, as the release left them in its defaults.
    private func fixture(_ name: String) throws -> [String: Data] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures/Legacy"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Data])
    }

    private func load(_ name: String) throws {
        for (key, value) in try fixture(name) {
            defaults.set(value, forKey: key)
        }
    }

    private var databaseIsEmpty: Bool {
        storage.records(RDFolder.self).isEmpty && storage.records(RDIdentity.self).isEmpty
            && storage.records(RDMachine.self).isEmpty && storage.records(RDSnippet.self).isEmpty
            && storage.records(RDPortForward.self).isEmpty && storage.pendingUploads().isEmpty
    }

    @discardableResult
    private func runImport(masterKey: String? = nil, forget: @escaping () -> Void = {}) -> Bool {
        let key = masterKey ?? master
        return LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { key }, forgetMasterKey: forget) == .imported
    }

    func testImportsWhat24Wrote() throws {
        try load("v2.4")
        var forgotten = false
        XCTAssertTrue(runImport { forgotten = true })
        XCTAssertTrue(forgotten)

        let identity = try XCTUnwrap(storage.record(RDIdentity.self, id: identityID))
        XCTAssertEqual(identity.username, "root")
        XCTAssertEqual(identity.password, "hunter2")
        XCTAssertEqual(identity.privateKey, "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n")
        XCTAssertEqual(identity.group, "Work")

        let server = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        XCTAssertEqual(server.fileTransferLoginPath, "/srv", "read from the attachment")
        XCTAssertEqual(server.associatedIdentity, identityID)
        XCTAssertEqual(storage.records(RDMachine.self).count, 2)
        XCTAssertEqual(storage.records(RDFolder.self).map(\.name), ["Production"])
        XCTAssertEqual(server.folderId, storage.records(RDFolder.self).first?.id)

        let snippet = try XCTUnwrap(storage.record(RDSnippet.self, id: snippetID))
        XCTAssertEqual(snippet.symbol, "clock")
        let forward = try XCTUnwrap(storage.record(RDPortForward.self, id: forwardID))
        XCTAssertEqual(forward.usingMachine, serverID)
        XCTAssertEqual(forward.targetPort, 80)
        XCTAssertEqual(storage.recentConnections().map(\.id), [serverID.uuidString, "ssh admin@example.com -p 2200"])

        for key in LegacyStoreImport.Key.sealed {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    func testImportsWhat262Wrote() throws {
        try load("v2.6.2")
        XCTAssertTrue(runImport())

        let server = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        XCTAssertEqual(server.transport, .cloudflareAccess)
        XCTAssertEqual(server.cloudflareServiceTokenID, "token-id")
        XCTAssertEqual(server.cloudflareServiceTokenSecret, "token-secret")
        XCTAssertEqual(server.fileTransferLoginPath, "/home/me")
        XCTAssertTrue(try XCTUnwrap(storage.record(RDIdentity.self, id: identityID)).useSSHAgent)
    }

    func testImportsA28InstallWithGroupsInEveryFormat() throws {
        try load("v2.8")
        XCTAssertTrue(runImport())

        let server = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        XCTAssertEqual(server.transport, .proxyJump)
        XCTAssertEqual(server.proxyJumpMachineID, jumpID)
        XCTAssertEqual(server.sshUsername, "deploy")
        XCTAssertEqual(server.remoteDesktopProtocol, .vnc)
        XCTAssertEqual(server.vncPort, "5901")
        XCTAssertEqual(server.vncPassword, "vnc-secret")
        XCTAssertTrue(server.uuTrueColor)

        let folders = storage.records(RDFolder.self)
        XCTAssertEqual(Set(folders.map(\.name)), ["Production", "UU", "Remote"])
        XCTAssertEqual(folders.first { $0.name == "UU" }?.source, .uuRemote(userID: "42"))
        XCTAssertEqual(server.folderId, folders.first { $0.name == "Production" }?.id)
        XCTAssertEqual(storage.record(RDMachine.self, id: jumpID)?.folderId, folders.first { $0.name == "Remote" }?.id)

        XCTAssertEqual(storage.record(RDIdentity.self, id: identityID)?.password, "hunter2", "RGCM1")
        XCTAssertEqual(storage.record(RDSnippet.self, id: snippetID)?.code, "uptime", "AES-CBC")
        XCTAssertEqual(storage.record(RDPortForward.self, id: forwardID)?.forwardOrientation, .listenRemote, "RGCM1")
        XCTAssertEqual(storage.recentConnections().map(\.machine), [jumpID])
        XCTAssertEqual(storage.knownHost(named: "[bastion]:22")?.key, Data([1, 2, 3]))
    }

    /// Two devices updating from the same old data make the same records:
    /// the same folder ids, the same old times, nothing for sync to tell
    /// apart or duplicate.
    func testTwoDevicesImportTheSameRecords() throws {
        try load("v2.8")
        XCTAssertTrue(runImport())
        let other = try TestStorage()
        let otherDefaults = try XCTUnwrap(UserDefaults(suiteName: "\(suite).other"))
        defer { otherDefaults.removePersistentDomain(forName: "\(suite).other") }
        for (key, value) in try fixture("v2.8") {
            otherDefaults.set(value, forKey: key)
        }
        XCTAssertEqual(LegacyStoreImport.runIfNeeded(into: other.storage, defaults: otherDefaults, masterKey: { self.master }, forgetMasterKey: {}), .imported)

        let folders = storage.records(RDFolder.self).sorted { $0.name < $1.name }
        XCTAssertEqual(folders, other.storage.records(RDFolder.self).sorted { $0.name < $1.name })
        XCTAssertEqual(folders.first { $0.name == "Remote" }?.id, RDFolder.id(named: "Remote"))
        XCTAssertEqual(folders.first { $0.name == "UU" }?.id, RDFolder.id(uuUserID: "42"))
        for server in storage.records(RDMachine.self) {
            XCTAssertEqual(try storage.mergeRemote(XCTUnwrap(other.storage.record(RDMachine.self, id: server.id))), .unchanged)
            XCTAssertLessThan(server.modified, Date(timeIntervalSinceReferenceDate: 60 * 60 * 24 * 60))
        }
    }

    /// A device that updates late, from data older than what another device
    /// changed since, does not win over that change.
    func testALateImportLosesToEditsMadeSince() throws {
        try load("v2.8")
        XCTAssertTrue(runImport())
        var edited = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        edited.name = "Edited"
        edited = try storage.save(edited)

        let late = try TestStorage()
        let lateDefaults = try XCTUnwrap(UserDefaults(suiteName: "\(suite).late"))
        defer { lateDefaults.removePersistentDomain(forName: "\(suite).late") }
        for (key, value) in try fixture("v2.8") {
            lateDefaults.set(value, forKey: key)
        }
        XCTAssertEqual(LegacyStoreImport.runIfNeeded(into: late.storage, defaults: lateDefaults, masterKey: { self.master }, forgetMasterKey: {}), .imported)
        let stale = try XCTUnwrap(late.storage.record(RDMachine.self, id: serverID))

        XCTAssertEqual(try storage.mergeRemote(stale), .keptLocal)
        XCTAssertEqual(try late.storage.mergeRemote(edited), .tookRemote)
        XCTAssertEqual(late.storage.record(RDMachine.self, id: serverID)?.name, "Edited")
    }

    /// A group that cannot be read stops everything: nothing is imported,
    /// nothing removed, the master key kept, and the next launch tries again.
    func testAnUnreadableGroupImportsNothingAndKeepsEverything() throws {
        var values = try fixture("v2.8")
        var snippets = try XCTUnwrap(values["snippetGroupEncrypted"])
        snippets[snippets.count - 1] ^= 0xFF
        values["snippetGroupEncrypted"] = snippets
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }

        var forgotten = false
        XCTAssertFalse(runImport { forgotten = true })
        XCTAssertFalse(forgotten)
        XCTAssertTrue(databaseIsEmpty)
        XCTAssertFalse(defaults.bool(forKey: LegacyStoreImport.doneKey))
        for (key, value) in values {
            XCTAssertEqual(defaults.data(forKey: key), value, key)
        }
    }

    func testTheWrongKeyImportsNothing() throws {
        try load("v2.4")
        XCTAssertFalse(runImport(masterKey: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertTrue(databaseIsEmpty)
        XCTAssertNotNil(defaults.object(forKey: "machineGroupEncrypted"))
    }

    /// The keychain refusing a write halfway leaves nothing behind, in the
    /// database or the keychain, and the next launch imports everything.
    func testAKeychainFailureHalfwayImportsNothing() throws {
        try load("v2.8")
        storage.close()
        var refusing = secrets!
        refusing.refusedAccounts = ["\(RDMachine.tableName).\(serverID.uuidString)"]
        storage = try RayonStorage(databaseURL: directory.appendingPathComponent("database.db"), secrets: refusing)

        XCTAssertFalse(runImport())
        XCTAssertTrue(databaseIsEmpty)
        XCTAssertNil(try secrets.data(for: "\(RDIdentity.tableName).\(identityID.uuidString)"), "the identity's password, written first, is gone again")
        XCTAssertNotNil(defaults.object(forKey: "machineGroupEncrypted"))
        XCTAssertFalse(defaults.bool(forKey: LegacyStoreImport.doneKey))

        storage.close()
        storage = try RayonStorage(databaseURL: directory.appendingPathComponent("database.db"), secrets: secrets)
        XCTAssertTrue(runImport())
        XCTAssertEqual(storage.record(RDMachine.self, id: serverID)?.vncPassword, "vnc-secret")
        XCTAssertEqual(storage.record(RDIdentity.self, id: identityID)?.password, "hunter2")
    }

    /// What the user saved while the old values could not be read does not
    /// stop them coming in later.
    func testRecordsSavedBeforeTheImportDoNotStopIt() throws {
        try storage.save(RDMachine(remoteAddress: "new", remotePort: "22", name: "Added"))
        try load("v2.4")
        XCTAssertTrue(runImport())
        XCTAssertEqual(Set(storage.records(RDMachine.self).map(\.name)), ["Added", "Inner", "Bastion"])
    }

    /// Another launch that finds the old values again (the flag lost, or
    /// defaults shared with another build) leaves what is saved alone.
    func testASecondLaunchNeverOverwritesTheDatabase() throws {
        try load("v2.4")
        XCTAssertTrue(runImport())
        var server = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        server.name = "Renamed"
        try storage.save(server)

        try load("v2.4")
        defaults.removeObject(forKey: LegacyStoreImport.doneKey)
        runImport()
        XCTAssertEqual(storage.record(RDMachine.self, id: serverID)?.name, "Renamed")
    }

    func testWithoutTheMasterKeyNothingIsTouchedAndTheUserIsTold() throws {
        try load("v2.4")
        let outcome = LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { nil }, forgetMasterKey: {})
        guard case let .blocked(reason) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(reason.contains("keychain"))
        XCTAssertNotNil(defaults.object(forKey: "machineGroupEncrypted"))
        XCTAssertFalse(defaults.bool(forKey: LegacyStoreImport.doneKey))

        // Saving something meanwhile does not end the attempts.
        try storage.save(RDMachine(remoteAddress: "new", remotePort: "22", name: "Added"))
        XCTAssertTrue(runImport())
        XCTAssertEqual(storage.records(RDMachine.self).count, 3)
    }

    func testUnreadableDataIsReportedToTheUser() throws {
        try load("v2.4")
        let outcome = LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { "6F9619FF-8B86-D011-B42D-00C04FC964FF" }, forgetMasterKey: {})
        guard case let .blocked(reason) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(reason.contains("its servers could not be decrypted"), reason)
    }

    /// Up to 2.4 the master key was kept under the name of the app's former
    /// maintainer; 2.8 still read it there, and so does the import.
    func testTheMasterKeyIsFoundUnderItsFormerName() throws {
        XCTAssertEqual(LegacyStoreImport.masterKeyItems.map(\.service), ["me.mizorewww.rayon.kcAccess", "wiki.qaq.rayon.kcAccess"])
        XCTAssertEqual(LegacyStoreImport.masterKeyItems.map(\.account), ["me.mizorewww.rayon.MasterCrypto", "wiki.qaq.rayon.MasterCrypto"])

        let items: [(service: String, account: String)] = [
            ("me.mizorewww.rayon.tests.current.\(UUID().uuidString)", "me.mizorewww.rayon.MasterCrypto"),
            ("me.mizorewww.rayon.tests.former.\(UUID().uuidString)", "wiki.qaq.rayon.MasterCrypto"),
        ]
        defer { LegacyStoreImport.removeMasterKey(items: items) }
        XCTAssertNil(LegacyStoreImport.readMasterKey(from: items))
        XCTAssertEqual(SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: items[1].service,
            kSecAttrAccount as String: items[1].account,
            kSecValueData as String: Data(master.utf8),
        ] as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(LegacyStoreImport.readMasterKey(from: items), master)

        try load("v2.4")
        XCTAssertEqual(LegacyStoreImport.runIfNeeded(
            into: storage, defaults: defaults,
            masterKey: { LegacyStoreImport.readMasterKey(from: items) },
            forgetMasterKey: { LegacyStoreImport.removeMasterKey(items: items) }
        ), .imported)
        XCTAssertNil(LegacyStoreImport.readMasterKey(from: items), "forgotten once imported")
    }

    /// 2.8's iCloud sync key is in the iCloud keychain, shared with the
    /// devices not updated yet: forgetting the master key leaves it.
    func testForgettingTheMasterKeyLeavesTheSyncKey() throws {
        let syncKey: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "me.mizorewww.rayon.sync.key",
            kSecAttrAccount as String: "me.mizorewww.rayon.tests.\(UUID().uuidString)",
        ]
        XCTAssertEqual(SecItemAdd(syncKey.merging([kSecValueData as String: Data("passphrase".utf8)]) { $1 } as CFDictionary, nil), errSecSuccess)
        defer { SecItemDelete(syncKey as CFDictionary) }

        LegacyStoreImport.removeMasterKey(items: [("me.mizorewww.rayon.tests.\(UUID().uuidString)", "me.mizorewww.rayon.MasterCrypto")])
        XCTAssertEqual(SecItemCopyMatching(syncKey as CFDictionary, nil), errSecSuccess)
    }
}
