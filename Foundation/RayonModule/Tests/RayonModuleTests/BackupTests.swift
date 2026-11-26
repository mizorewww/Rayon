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

    func testARoundTripKeepsEverythingWithThePassword() throws {
        let (machine, identity) = seed()
        try source.store().exportBackup(to: file, includeSecrets: true, password: "correct horse")
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

    /// A wrong password is refused, never answered with another key, and
    /// nothing is restored.
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

    func testAWrongPasswordIsRefused() throws {
        _ = seed()
        try source.store().exportBackup(to: file, includeSecrets: true, password: "correct horse")
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
        XCTAssertThrowsError(try source.store().exportBackup(to: file, includeSecrets: true, password: "")) {
            XCTAssertEqual($0 as? BackupError, .passwordRequired)
        }
    }

    /// Without its secrets a backup needs no password, and restoring it
    /// keeps the passwords already here.
    func testABackupWithoutSecretsKeepsTheOnesHere() throws {
        let (_, identity) = seed()
        try source.store().exportBackup(to: file, includeSecrets: false, password: nil)
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
}
