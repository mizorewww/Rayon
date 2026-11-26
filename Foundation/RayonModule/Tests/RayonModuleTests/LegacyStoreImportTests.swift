@testable import RayonModule
import XCTest

/// The previous release's store, as it wrote it, comes into the database.
final class LegacyStoreImportTests: XCTestCase {
    private var directory: URL!
    private var secrets: SecretStore!
    private var storage: RayonStorage!
    private var defaults: UserDefaults!
    private let suite = "me.mizorewww.rayon.tests.legacy.\(UUID().uuidString)"
    private let master = "test-master-key"

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

    private func seal(_ object: Any) throws -> Data {
        let plist = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        return try LegacyStoreImport.Opener(masterKey: master).seal(plist)
    }

    func testImportsTheCurrentFormatAndRemovesIt() throws {
        let identityID = UUID()
        let jumpID = UUID()
        let serverID = UUID()
        let folderID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(try seal(["id": UUID().uuidString, "identities": [[
            "id": identityID.uuidString, "username": "root", "password": "hunter2",
            "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----", "publicKey": "ssh-ed25519 AAAA",
            "lastRecentUsed": date, "comment": "", "group": "", "authenticAutomatically": true,
            "attachment": ["auth.sshAgent": "1"],
        ]]]), forKey: "identityGroupEncrypted")
        defaults.set(try seal(["id": UUID().uuidString, "machines": [
            [
                "id": jumpID.uuidString, "remoteAddress": "bastion", "remotePort": "22", "name": "Bastion",
                "group": "", "lastConnection": date, "lastBanner": "", "comment": "", "attachment": [:],
            ],
            [
                "id": serverID.uuidString, "remoteAddress": "10.0.0.2", "remotePort": "2222", "name": "Inner",
                "group": "Production", "lastConnection": date, "lastBanner": "hi", "comment": "c",
                "associatedIdentity": identityID.uuidString, "attachment": [:], "sshUsername": "deploy",
                "transport": "proxy-jump", "proxyJumpMachineID": jumpID.uuidString, "vncPassword": "vnc",
                "uuFPS": 30,
            ],
            ["id": "not a record"],
        ]]), forKey: "machineGroupEncrypted")
        defaults.set(try seal(["folders": [
            ["id": folderID.uuidString, "name": "UU", "source": ["uuRemote": ["userID": "42"]]],
        ]]), forKey: "folderGroupEncrypted")
        defaults.set(try seal(["id": UUID().uuidString, "snippets": [[
            "id": UUID().uuidString, "name": "Uptime", "group": "", "code": "uptime", "comment": "",
            "attachment": ["sfAvatar": "clock"],
        ]]]), forKey: "snippetGroupEncrypted")
        defaults.set(try seal(["id": UUID().uuidString, "forwards": [[
            "id": UUID().uuidString, "forwardOrientation": "Dynamic", "bindPort": 1080,
            "targetHost": "", "targetPort": 0, "usingMachine": serverID.uuidString, "attachment": [:],
        ]]]), forKey: "portForwardEncrypted")
        defaults.set(try seal(["[bastion]:22": "ssh-ed25519 " + Data([1, 2, 3]).base64EncodedString()]), forKey: "me.mizorewww.rayon.knownHosts")
        defaults.set(try seal(2), forKey: "machineRedacted")

        XCTAssertTrue(LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { self.master }, forgetMasterKey: {}))

        let identity = try XCTUnwrap(storage.record(RDIdentity.self, id: identityID))
        XCTAssertEqual(identity.password, "hunter2")
        XCTAssertTrue(identity.useSSHAgent)

        let machines = storage.records(RDMachine.self)
        XCTAssertEqual(machines.count, 2, "the unreadable server is skipped, the rest kept")
        let server = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        XCTAssertEqual(server.associatedIdentity, identityID)
        XCTAssertEqual(server.proxyJumpMachineID, jumpID)
        XCTAssertEqual(server.transport, .proxyJump)
        XCTAssertEqual(server.sshUsername, "deploy")
        XCTAssertEqual(server.vncPassword, "vnc")
        XCTAssertEqual(server.uuFPS, 30)
        XCTAssertEqual(server.vncPort, "5900")
        XCTAssertEqual(server.fileTransferLoginPath, "/")

        let folders = storage.records(RDFolder.self)
        XCTAssertEqual(Set(folders.map(\.name)), ["UU", "Production"])
        XCTAssertEqual(folders.first { $0.id == folderID }?.source, .uuRemote(userID: "42"))
        XCTAssertEqual(server.folderId, folders.first { $0.name == "Production" }?.id)

        XCTAssertEqual(storage.records(RDSnippet.self).first?.symbol, "clock")
        XCTAssertEqual(storage.records(RDPortForward.self).first?.forwardOrientation, .dynamicSOCKS)
        XCTAssertEqual(storage.knownHost(named: "[bastion]:22")?.key, Data([1, 2, 3]))
        XCTAssertEqual(defaults.integer(forKey: RayonStore.Key.machineRedacted), 2)

        XCTAssertNil(defaults.object(forKey: "machineGroupEncrypted"))
        XCTAssertNil(defaults.object(forKey: "identityGroupEncrypted"))
        XCTAssertFalse(LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { self.master }, forgetMasterKey: {}))
    }

    /// Another launch that finds the old values again (the flag lost, or
    /// defaults shared with another build) leaves what is saved alone.
    func testASecondLaunchNeverOverwritesTheDatabase() throws {
        let serverID = UUID()
        let old = try seal(["machines": [[
            "id": serverID.uuidString, "remoteAddress": "old", "remotePort": "22", "name": "Old",
            "group": "", "lastConnection": Date(), "lastBanner": "", "comment": "", "attachment": [:],
        ]]])
        defaults.set(old, forKey: "machineGroupEncrypted")
        XCTAssertTrue(LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { self.master }, forgetMasterKey: {}))
        var server = try XCTUnwrap(storage.record(RDMachine.self, id: serverID))
        server.name = "Renamed"
        try storage.save(server)
        try storage.save(RDMachine(remoteAddress: "new", remotePort: "22", name: "Added"))

        defaults.set(old, forKey: "machineGroupEncrypted")
        defaults.removeObject(forKey: LegacyStoreImport.doneKey)
        XCTAssertFalse(LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { self.master }, forgetMasterKey: {}))
        XCTAssertEqual(Set(storage.records(RDMachine.self).map(\.name)), ["Renamed", "Added"])
    }

    func testWithoutTheMasterKeyNothingIsTouched() throws {
        defaults.set(try seal(["machines": []]), forKey: "machineGroupEncrypted")
        XCTAssertFalse(LegacyStoreImport.runIfNeeded(into: storage, defaults: defaults, masterKey: { nil }, forgetMasterKey: {}))
        XCTAssertNotNil(defaults.object(forKey: "machineGroupEncrypted"))
        XCTAssertFalse(defaults.bool(forKey: LegacyStoreImport.doneKey))
    }
}
