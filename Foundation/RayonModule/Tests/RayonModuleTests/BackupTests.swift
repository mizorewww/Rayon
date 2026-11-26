//
//  BackupTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import RayonTerminal
import XCTest

@MainActor
final class BackupTests: XCTestCase {
    private var source: TestStorage!
    private var target: TestStorage!
    private var file: URL!

    override func setUp() async throws {
        source = try TestStorage()
        target = try TestStorage()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(DataBackup.fileExtension)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file)
        source = nil
        target = nil
    }

    private func seed() -> (RDMachine, RDIdentity) {
        let store = source.store()
        let folder = store.createFolder(named: "prod")
        let identity = RDIdentity(username: "root", password: "hunter2", privateKey: "KEY")
        store.save(identity)
        var machine = RDMachine(remoteAddress: "10.0.0.1", remotePort: "22", name: "web", folderId: folder.id, associatedIdentity: identity.id)
        machine.vncPassword = "vnc"
        store.save(machine)
        store.save(RDSnippet(name: "uptime", code: "uptime"))
        store.save(RDPortForward(forwardOrientation: .dynamicSOCKS, bindPort: 1080, usingMachine: machine.id))
        try? source.storage.saveKnownHost(KnownHostRecord(name: "[10.0.0.1]:22", type: "ssh-ed25519", key: Data([1]), added: Date()))
        return (machine, identity)
    }

    func testARoundTripKeepsEverythingWithThePassword() async throws {
        let (machine, identity) = seed()
        try await source.store().exportBackup(to: file, includeSecrets: true, password: "correct horse")
        XCTAssertTrue(DataBackup.needsPassword(file))

        let contents = try DataBackup.read(file, password: "correct horse")
        let store = target.store()
        store.restore(contents)
        XCTAssertEqual(store.identity(identity.id)?.password, "hunter2")
        XCTAssertEqual(store.identity(identity.id)?.privateKey, "KEY")
        XCTAssertEqual(store.machine(machine.id)?.vncPassword, "vnc")
        XCTAssertEqual(store.machine(machine.id)?.associatedIdentity, identity.id)
        XCTAssertEqual(store.folderName(of: store.machine(machine.id)!), "prod")
        XCTAssertEqual(store.snippets.map(\.name), ["uptime"])
        XCTAssertEqual(store.portForwards.count, 1)
        XCTAssertNotNil(target.storage.knownHost(named: "[10.0.0.1]:22"))

        // Nothing of the secrets is readable in the file.
        let raw = try Data(contentsOf: file)
        XCTAssertNil(raw.range(of: Data("hunter2".utf8)))
    }

    /// A folder of the backup whose name is taken here is that folder: no
    /// second folder of the name, and the servers in it go there. A server
    /// whose folder is in neither goes to the default one.
    func testFoldersAreMergedByName() throws {
        let (machine, _) = seed()
        var orphan = RDMachine(remoteAddress: "10.0.0.9", remotePort: "22", name: "orphan", folderId: UUID())
        orphan = try source.storage.save(orphan)
        try DataBackup.export(from: source.storage, to: file, includeSecrets: false, password: nil)

        let store = target.store()
        let here = store.createFolder(named: "prod")
        store.restore(try DataBackup.read(file, password: nil))
        XCTAssertEqual(store.folders.map(\.name), ["prod"])
        XCTAssertEqual(store.machine(machine.id)?.folderId, here.id)
        XCTAssertNil(store.machine(orphan.id)?.folderId)

        // One whose folder went away later is listed with the default ones.
        var stranded = RDMachine(remoteAddress: "10.0.0.8", remotePort: "22", name: "stranded", folderId: UUID())
        stranded = try target.storage.save(stranded)
        store.reload()
        XCTAssertTrue(store.machines(inFolder: nil).contains { $0.id == stranded.id })
    }

    /// A wrong password is refused, never answered with another key, and
    /// nothing is restored.
    func testAWrongPasswordIsRefused() async throws {
        _ = seed()
        try await source.store().exportBackup(to: file, includeSecrets: true, password: "correct horse")
        XCTAssertThrowsError(try DataBackup.read(file, password: "battery staple")) {
            XCTAssertEqual($0 as? BackupError, .wrongPassword)
        }
        XCTAssertThrowsError(try DataBackup.read(file, password: nil)) {
            XCTAssertEqual($0 as? BackupError, .passwordRequired)
        }
        XCTAssertTrue(target.store().machines.isEmpty)
    }

    func testSecretsNeedAPassword() {
        _ = seed()
        XCTAssertThrowsError(try DataBackup.export(from: source.storage, to: file, includeSecrets: true, password: "")) {
            XCTAssertEqual($0 as? BackupError, .passwordRequired)
        }
    }

    /// Without its secrets a backup needs no password, and restoring it
    /// keeps the passwords already here.
    func testABackupWithoutSecretsKeepsTheOnesHere() async throws {
        let (_, identity) = seed()
        try await source.store().exportBackup(to: file, includeSecrets: false, password: nil)
        XCTAssertFalse(DataBackup.needsPassword(file))

        let contents = try DataBackup.read(file, password: nil)
        XCTAssertEqual(contents.identities.first?.password, "")
        let store = source.store()
        store.restore(contents)
        XCTAssertEqual(store.identity(identity.id)?.password, "hunter2")
    }

    func testOtherFilesAreNotBackups() throws {
        try Data("not a zip".utf8).write(to: file)
        XCTAssertThrowsError(try DataBackup.read(file, password: nil)) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
    }

    /// A terminal settings file of its own, removed after the test.
    private func terminalSettings(_ text: String? = nil) throws -> TerminalSettings {
        let folder = FileManager.default.temporaryDirectory.appending(path: "rayon-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "config.ghostty")
        if let text {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return TerminalSettings(fileURL: url, defaults: UserDefaults(suiteName: "rayon-tests-\(UUID().uuidString)")!)
    }

    func testPreferencesRoundTripWithoutDeviceState() throws {
        let suite = "rayon-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(21, forKey: "me.mizorewww.rayon.terminalFontSize")
        defaults.set(true, forKey: "me.mizorewww.rayon.sync.enabled")
        let terminal = try terminalSettings("# mine\nbackground = #123456\n")
        try PreferencesBackup.export(from: defaults, terminal: terminal, to: file)
        XCTAssertThrowsError(try DataBackup.read(file, password: nil)) {
            XCTAssertEqual($0 as? BackupError, .wrongKind)
        }

        let restoredSuite = "rayon-tests-\(UUID().uuidString)"
        let restored = try XCTUnwrap(UserDefaults(suiteName: restoredSuite))
        defer { restored.removePersistentDomain(forName: restoredSuite) }
        let restoredTerminal = try terminalSettings()
        defer { try? restoredTerminal.load(TerminalSettings.shared.contents) }
        try PreferencesBackup.restore(from: file, into: restored, terminal: restoredTerminal)
        XCTAssertEqual(restored.integer(forKey: "me.mizorewww.rayon.terminalFontSize"), 21)
        XCTAssertNil(restored.object(forKey: "me.mizorewww.rayon.sync.enabled"))
        XCTAssertEqual(restoredTerminal.contents, "# mine\nbackground = #123456\n")
        XCTAssertEqual(try String(contentsOf: restoredTerminal.fileURL, encoding: .utf8), "# mine\nbackground = #123456\n")
    }

    /// A backup from before config.ghostty kept the terminal settings among the preferences.
    func testOlderPreferencesBackupRestoresTerminalSettings() throws {
        let suite = "rayon-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = ##"{"document":{"overrides":{"background":["#654321"]}}}"##
        let values: [String: Any] = ["me.mizorewww.rayon.ghosttyConfiguration.v1": Data(legacy.utf8)]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try BackupArchive.write([PreferencesBackup.preferencesFile: data], kind: .preferences, includesSecrets: false, password: nil, to: file)
        let terminal = try terminalSettings()
        defer { try? terminal.load(TerminalSettings.shared.contents) }
        try PreferencesBackup.restore(from: file, into: defaults, terminal: terminal)
        XCTAssertTrue(terminal.contents.contains("background = #654321"))
        XCTAssertNil(defaults.object(forKey: "me.mizorewww.rayon.ghosttyConfiguration.v1"))
    }

    /// A backup asking for more key derivation rounds than any Rayon writes
    /// is refused at once, not derived for hours (or crashed on).
    func testAbsurdKeyDerivationIsRefused() {
        for rounds in [0, BackupArchive.maxPBKDFRounds + 1, Int(UInt32.max) + 1] {
            XCTAssertThrowsError(try BackupArchive.deriveKey(
                password: "pw",
                encryption: BackupManifest.Encryption(salt: Data([1, 2, 3]), rounds: rounds)
            ))
        }
    }

    /// The counts say what was saved; a server whose jumps would loop with
    /// the servers here is cut free rather than refused.
    func testTheCountsAreWhatWasSaved() throws {
        let store = target.store()
        var here = RDMachine(remoteAddress: "here", remotePort: "22", name: "here")
        var restored = RDMachine(remoteAddress: "restored", remotePort: "22", name: "restored")
        restored.transport = .proxyJump
        restored.proxyJumpMachineID = here.id
        XCTAssertTrue(store.save(here))
        here.transport = .proxyJump
        here.proxyJumpMachineID = restored.id
        var contents = DataBackupContents()
        contents.machines = [restored, here]
        let result = store.restore(contents)
        XCTAssertEqual(result.machines, 2)
        XCTAssertEqual(result.refused, 0)
        for machine in store.machines {
            XCTAssertNoThrow(try machine.proxyJumpChain { store.machine($0) })
        }
    }
}

/// The backups 2.7 and 2.8 exported, written by 2.8's own code (see
/// LegacyStoreImportTests): v2.8-backup.json as plain JSON,
/// v2.8-backup-passphrase.json sealed with the passphrase "correct horse".
/// Their server "Inner" jumps through "Bastion", which jumps back.
@MainActor
final class LegacyBackupTests: XCTestCase {
    private var target: TestStorage!

    override func setUp() async throws {
        target = try TestStorage()
    }

    override func tearDown() async throws {
        target = nil
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Legacy"))
    }

    private let identityID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let serverID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let jumpID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private func check(_ contents: DataBackupContents) throws {
        let store = target.store()
        let result = store.restore(contents)
        XCTAssertEqual(result, .init(machines: 2, identities: 1, snippets: 1, forwards: 1, refused: 0))

        let identity = try XCTUnwrap(store.identity(identityID))
        XCTAssertEqual(identity.password, "hunter2")
        XCTAssertEqual(identity.privateKey, "KEY")
        let server = try XCTUnwrap(store.machine(serverID))
        XCTAssertEqual(server.sshUsername, "deploy")
        XCTAssertEqual(server.vncPassword, "vnc-secret")
        XCTAssertEqual(server.vncPort, "5901")
        XCTAssertEqual(store.folderName(of: server), "Production")
        XCTAssertEqual(store.folderName(of: try XCTUnwrap(store.machine(jumpID))), "Lost", "a folder only a server named")
        XCTAssertEqual(store.snippets.first?.symbol, "clock")
        XCTAssertEqual(store.portForwards.first?.bindPort, 8080)
        for machine in store.machines {
            XCTAssertNoThrow(try machine.proxyJumpChain { store.machine($0) }, "the loop is cut")
        }
    }

    func testAPlainBackupIsRestored() throws {
        let url = try fixture("v2.8-backup")
        XCTAssertFalse(DataBackup.needsPassword(url))
        try check(DataBackup.read(url, password: nil))
    }

    func testASealedBackupNeedsItsPassphrase() throws {
        let url = try fixture("v2.8-backup-passphrase")
        XCTAssertTrue(DataBackup.needsPassword(url))
        XCTAssertThrowsError(try DataBackup.read(url, password: nil)) { XCTAssertEqual($0 as? BackupError, .passwordRequired) }
        XCTAssertThrowsError(try DataBackup.read(url, password: "wrong")) { XCTAssertEqual($0 as? BackupError, .wrongPassword) }
        try check(DataBackup.read(url, password: " correct horse "))
    }

    func testOtherFilesAreNotBackups() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"hello\": 1}".utf8).write(to: url)
        XCTAssertThrowsError(try DataBackup.read(url, password: nil)) { XCTAssertEqual($0 as? BackupError, .notABackup) }
    }
}

/// The original app's hidden importer: its stored values as a property
/// list, each sealed under a key pasted after it. The 2.4 and 2.8 store
/// fixtures are such values, under the fixtures' master key.
@MainActor
final class PastedImportTests: XCTestCase {
    private var target: TestStorage!
    private let key = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"

    override func setUp() async throws {
        target = try TestStorage()
    }

    override func tearDown() async throws {
        target = nil
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures/Legacy")))
    }

    func testPastedDataIsImportedWithItsKey() throws {
        let store = target.store()
        let result = try store.importPasted(fixture("v2.4"), key: key)
        XCTAssertEqual(result.machines, 2)
        XCTAssertEqual(result.identities, 1)
        XCTAssertEqual(store.identities.first?.password, "hunter2")
        XCTAssertEqual(store.folderName(of: try XCTUnwrap(store.machines.first { $0.name == "Inner" })), "Production")

        XCTAssertEqual(try store.importPasted(fixture("v2.8"), key: key).machines, 2)
        XCTAssertEqual(store.machines.first { $0.name == "Inner" }?.vncPassword, "vnc-secret")
    }

    func testAWrongKeyImportsNothing() throws {
        let store = target.store()
        XCTAssertThrowsError(try store.importPasted(fixture("v2.8"), key: "not the key at all")) {
            XCTAssertEqual($0 as? BackupError, .wrongPassword)
        }
        XCTAssertTrue(store.machines.isEmpty)
        XCTAssertThrowsError(try store.importPasted(Data("hello".utf8), key: key))
    }
}
