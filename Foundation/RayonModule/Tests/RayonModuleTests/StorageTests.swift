//
//  StorageTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import WCDBSwift
import XCTest

final class StorageTests: XCTestCase {
    private var test: TestStorage!
    private var storage: RayonStorage { test.storage }

    override func setUpWithError() throws {
        test = try TestStorage()
    }

    override func tearDown() {
        test = nil
    }

    private func queue() throws -> [UploadQueueEntry] {
        try storage.db.getObjects(fromTable: UploadQueueEntry.tableName)
    }

    /// Dates as the database keeps them; a Date's sub-millisecond part
    /// does not survive.
    private static let when = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Schema

    func testEveryRecordTypeRoundTrips() throws {
        let folder = try storage.save(RDFolder(name: "prod", source: .uuRemote(userID: "42")))
        var identity = RDIdentity(username: "root", password: "pw", lastRecentUsed: Self.when)
        identity.privateKey = "-----BEGIN KEY-----"
        identity.useSSHAgent = true
        identity = try storage.save(identity)
        var machine = RDMachine(remoteAddress: "10.0.0.1", remotePort: "2222", name: "web", folderId: folder.id, lastConnection: Self.when, associatedIdentity: identity.id)
        machine.transport = .cloudflareAccess
        machine.remoteDesktopProtocol = .vnc
        machine.vncPassword = "vnc"
        machine.cloudflareServiceTokenSecret = "token"
        machine.uuFPS = 120
        machine = try storage.save(machine)
        var snippet = RDSnippet(name: "uptime", code: "uptime")
        snippet.symbol = "clock"
        snippet = try storage.save(snippet)
        let forward = try storage.save(RDPortForward(forwardOrientation: .dynamicSOCKS, bindPort: 1080, usingMachine: machine.id))

        XCTAssertEqual(storage.records(RDFolder.self), [folder])
        XCTAssertEqual(storage.records(RDIdentity.self), [identity])
        XCTAssertEqual(storage.records(RDMachine.self), [machine])
        XCTAssertEqual(storage.records(RDSnippet.self), [snippet])
        XCTAssertEqual(storage.records(RDPortForward.self), [forward])
        XCTAssertEqual(storage.record(RDMachine.self, id: machine.id)?.vncPassword, "vnc")
    }

    /// Passwords and keys go to the keychain; the database never holds them.
    /// A save is in the file when it returns: another connection to the
    /// database, as the next launch opens it, reads it.
    func testSavesAreInTheFileAtOnce() throws {
        let machine = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        let other = Database(at: storage.databaseURL.path)
        defer { other.close() }
        let row: RDMachine? = try other.getObject(fromTable: RDMachine.tableName)
        XCTAssertEqual(row?.id, machine.id)
    }

    func testSecretsStayOutOfTheDatabase() throws {
        let identity = try storage.save(RDIdentity(username: "root", password: "hunter2"))
        let row: RDIdentity? = try storage.db.getObject(fromTable: RDIdentity.tableName)
        XCTAssertEqual(row?.password, "")
        XCTAssertEqual(storage.record(RDIdentity.self, id: identity.id)?.password, "hunter2")
        let raw = try Data(contentsOf: storage.databaseURL)
        XCTAssertNil(raw.range(of: Data("hunter2".utf8)))
    }

    func testDeletionLeavesATombstoneAndForgetsTheSecrets() throws {
        let identity = try storage.save(RDIdentity(username: "root", password: "pw"))
        try storage.delete(RDIdentity.self, ids: [identity.id])
        XCTAssertTrue(storage.records(RDIdentity.self).isEmpty)
        XCTAssertEqual(storage.row(RDIdentity.self, id: identity.id)?.removed, true)
        XCTAssertNil(try test.secrets.data(for: identity.secretAccount))
        // Not while the deletion has yet to reach iCloud.
        storage.purgeTombstones(now: Date().addingTimeInterval(RayonStorage.tombstoneLifetime + 1))
        XCTAssertNotNil(storage.row(RDIdentity.self, id: identity.id))
        try storage.db.delete(fromTable: UploadQueueEntry.tableName)
        storage.purgeTombstones(now: Date().addingTimeInterval(RayonStorage.tombstoneLifetime + 1))
        XCTAssertNil(storage.row(RDIdentity.self, id: identity.id))
    }

    // MARK: Upload queue

    func testChangesAreQueuedOncePerRecord() throws {
        var machine = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        machine.name = "b"
        machine = try storage.save(machine)
        let entries = try queue()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.objectId, machine.id)
        XCTAssertEqual(entries.first?.modified, machine.modified)
    }

    /// The last banner and connection are this device's: writing them
    /// alone neither marks the server changed nor sends it anywhere.
    func testLocalStateIsNotAChange() throws {
        let machine = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        try storage.db.delete(fromTable: UploadQueueEntry.tableName)
        var connected = machine
        connected.lastBanner = "Welcome"
        connected.lastConnection = Date().addingTimeInterval(100)
        let saved = try storage.save(connected)
        XCTAssertEqual(saved.modified, machine.modified)
        XCTAssertTrue(try queue().isEmpty)
        XCTAssertEqual(storage.record(RDMachine.self, id: machine.id)?.lastBanner, "Welcome")
    }

    // MARK: Merge

    func testTheLaterChangeWins() throws {
        var local = RDMachine(remoteAddress: "a", remotePort: "22", name: "here")
        local.modified = Date(timeIntervalSince1970: 100)
        local.lastBanner = "local banner"
        var remote = local
        remote.name = "there"
        remote.lastBanner = ""

        remote.modified = Date(timeIntervalSince1970: 200)
        guard case let .takeRemote(merged) = RecordMerge.resolve(local: local, remote: remote) else {
            return XCTFail("the newer remote change should win")
        }
        XCTAssertEqual(merged.name, "there")
        XCTAssertEqual(merged.lastBanner, "local banner")

        remote.modified = Date(timeIntervalSince1970: 50)
        XCTAssertEqual(RecordMerge.resolve(local: local, remote: remote), .keepLocal)
        remote.modified = local.modified
        XCTAssertEqual(RecordMerge.resolve(local: local, remote: remote), .same)
        XCTAssertEqual(RecordMerge.resolve(local: nil, remote: remote), .takeRemote(remote))
    }

    func testPayloadCarriesTheSecrets() throws {
        var identity = RDIdentity(username: "root", password: "pw", lastRecentUsed: Self.when)
        identity.modified = Date(timeIntervalSince1970: 1_700_000_000.123)
        let data = try RecordPayload(identity).encoded()
        XCTAssertEqual(try RecordPayload<RDIdentity>.decode(data), identity)
    }

    // MARK: Validation

    func testProxyJumpCyclesAreFound() throws {
        var a = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        var b = RDMachine(remoteAddress: "b", remotePort: "22", name: "b")
        let c = RDMachine(remoteAddress: "c", remotePort: "22", name: "c")
        a.transport = .proxyJump
        a.proxyJumpMachineID = b.id
        b.transport = .proxyJump
        b.proxyJumpMachineID = c.id
        let all = [a, b, c]
        func lookup(_ id: UUID) -> RDMachine? { all.first { $0.id == id } }
        XCTAssertEqual(try a.proxyJumpChain(lookup: lookup).map(\.name), ["c", "b"])
        XCTAssertEqual(a.getCommand(lookup: lookup), "ssh -J c,b a")

        b.proxyJumpMachineID = a.id
        let looped = [a, b]
        XCTAssertThrowsError(try a.proxyJumpChain { id in looped.first { $0.id == id } })
        var selfJump = c
        selfJump.transport = .proxyJump
        selfJump.proxyJumpMachineID = c.id
        XCTAssertThrowsError(try selfJump.proxyJumpChain { _ in selfJump })
    }

    func testForwardsAreCheckedPerKind() {
        let machine = UUID()
        XCTAssertTrue(RDPortForward(forwardOrientation: .dynamicSOCKS, bindPort: 1080, usingMachine: machine).isComplete)
        XCTAssertFalse(RDPortForward(forwardOrientation: .dynamicSOCKS, bindPort: 0, usingMachine: machine).isComplete)
        XCTAssertFalse(RDPortForward(forwardOrientation: .dynamicSOCKS, bindPort: 1080).isComplete)
        XCTAssertFalse(RDPortForward(forwardOrientation: .listenLocal, bindPort: 8080, usingMachine: machine).isComplete)
        XCTAssertTrue(RDPortForward(forwardOrientation: .listenLocal, bindPort: 8080, targetHost: "db", targetPort: 5432, usingMachine: machine).isComplete)
        XCTAssertFalse(RDPortForward(forwardOrientation: .listenRemote, bindPort: 8080, targetHost: "db", targetPort: 0, usingMachine: machine).isComplete)
    }

    @MainActor
    func testTheStoreRefusesLoopsAndIncompleteForwards() {
        let store = test.store()
        var a = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        a.transport = .proxyJump
        a.proxyJumpMachineID = a.id
        XCTAssertFalse(store.save(a))
        XCTAssertNil(store.machine(a.id))
        XCTAssertFalse(store.save(RDPortForward(forwardOrientation: .listenLocal, bindPort: 80)))
        XCTAssertTrue(store.portForwards.isEmpty)
    }
}
