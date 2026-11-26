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

    @discardableResult
    private func runImport(masterKey: String? = nil, forget: @escaping () -> Void = {}) -> Bool {
        let key = masterKey ?? master
        return LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { key }, forgetMasterKey: forget)
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
        XCTAssertFalse(storage.hasAnyRecord)
        XCTAssertFalse(defaults.bool(forKey: LegacyStoreImport.doneKey))
        for (key, value) in values {
            XCTAssertEqual(defaults.data(forKey: key), value, key)
        }
    }

    func testTheWrongKeyImportsNothing() throws {
        try load("v2.4")
        XCTAssertFalse(runImport(masterKey: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertFalse(storage.hasAnyRecord)
        XCTAssertNotNil(defaults.object(forKey: "machineGroupEncrypted"))
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

    func testWithoutTheMasterKeyNothingIsTouched() throws {
        try load("v2.4")
        XCTAssertFalse(LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { nil }, forgetMasterKey: {}))
        XCTAssertNotNil(defaults.object(forKey: "machineGroupEncrypted"))
        XCTAssertFalse(defaults.bool(forKey: LegacyStoreImport.doneKey))
    }
}
