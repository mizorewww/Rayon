//
//  BackupTests.swift
//  RayonModuleTests
//

@testable import RayonModule
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

    func testPreferencesRoundTripWithoutDeviceState() throws {
        let suite = "rayon-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(21, forKey: "me.mizorewww.rayon.terminalFontSize")
        defaults.set(true, forKey: "me.mizorewww.rayon.sync.enabled")
        try PreferencesBackup.export(from: defaults, to: file)
        XCTAssertThrowsError(try DataBackup.read(file, password: nil)) {
            XCTAssertEqual($0 as? BackupError, .wrongKind)
        }

        let restoredSuite = "rayon-tests-\(UUID().uuidString)"
        let restored = try XCTUnwrap(UserDefaults(suiteName: restoredSuite))
        defer { restored.removePersistentDomain(forName: restoredSuite) }
        try PreferencesBackup.restore(from: file, into: restored)
        XCTAssertEqual(restored.integer(forKey: "me.mizorewww.rayon.terminalFontSize"), 21)
        XCTAssertNil(restored.object(forKey: "me.mizorewww.rayon.sync.enabled"))
    }
}
