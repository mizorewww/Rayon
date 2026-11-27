//
//  StorageTests.swift
//  RayonModuleTests
//

@testable import RayonModule
@preconcurrency import WCDBSwift
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
        var unchanged = local
        unchanged.lastBanner = ""
        XCTAssertEqual(RecordMerge.resolve(local: local, remote: unchanged), .same)
        XCTAssertEqual(RecordMerge.resolve(local: nil, remote: remote), .takeRemote(remote))
    }

    /// Two devices' first app settings, both stamped as old: the same one
    /// wins on both, so they end up with the same settings.
    func testVersionsChangedAtTheSameTimeConverge() throws {
        var mine = RDAppSettings(entries: [RayonStore.Key.timeout: .int(12)])
        mine.modified = Date(timeIntervalSince1970: 0)
        var theirs = RDAppSettings(entries: [RayonStore.Key.timeout: .int(30)])
        theirs.modified = mine.modified

        let here = RecordMerge.resolve(local: mine, remote: theirs)
        let there = RecordMerge.resolve(local: theirs, remote: mine)
        let winnerHere = here == .keepLocal ? mine : (here == .takeRemote(theirs) ? theirs : nil)
        let winnerThere = there == .keepLocal ? theirs : (there == .takeRemote(mine) ? mine : nil)
        XCTAssertNotNil(winnerHere)
        XCTAssertEqual(winnerHere, winnerThere)
        XCTAssertEqual(RecordMerge.resolve(local: mine, remote: mine), .same)
    }

    /// A version from a device whose clock is ahead is not newer than an
    /// edit made after it here: the edit counts as made just after it.
    func testAnEditWinsOverAVersionFromAClockAhead() throws {
        let server = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "here"))
        var ahead = server
        ahead.name = "from the future"
        ahead.modified = Date().addingTimeInterval(3600).wholeMilliseconds
        XCTAssertEqual(try storage.mergeRemote(ahead), .tookRemote)

        var edited = try XCTUnwrap(storage.record(RDMachine.self, id: server.id))
        edited.name = "edited"
        edited = try storage.save(edited)
        XCTAssertEqual(edited.modified.millisecondsSince1970, ahead.modified.millisecondsSince1970 + 1)
        guard case let .takeRemote(merged) = RecordMerge.resolve(local: ahead, remote: edited) else {
            return XCTFail("the edit should win")
        }
        XCTAssertEqual(merged.name, "edited")

        try storage.delete(RDMachine.self, ids: [server.id])
        let tombstone = try XCTUnwrap(storage.row(RDMachine.self, id: server.id))
        XCTAssertEqual(tombstone.modified.millisecondsSince1970, edited.modified.millisecondsSince1970 + 1)
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

    /// A jump server that would lead back is listed but cannot be chosen;
    /// a remote desktop never reached over SSH can, as it may run sshd too.
    /// A server whose jumps loop already (from another device, or a
    /// backup) still saves what it records of its connections.
    @MainActor
    func testJumpServersThatWouldLoopCannotBeChosen() throws {
        let store = test.store()
        let a = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        var b = RDMachine(remoteAddress: "b", remotePort: "22", name: "b")
        b.transport = .proxyJump
        b.proxyJumpMachineID = a.id
        var desktop = RDMachine(remoteAddress: "vnc", remotePort: "22", name: "vnc")
        desktop.remoteDesktopProtocol = .vnc
        XCTAssertTrue(store.save(a))
        XCTAssertTrue(store.save(b))
        XCTAssertTrue(store.save(desktop))
        func choosable(_ id: RDMachine.ID?) -> Set<String> {
            Set(store.jumpServerChoices(for: id).filter { $0.unavailableReason == nil }.map(\.machine.name))
        }
        XCTAssertEqual(choosable(a.id), ["vnc"], "b jumps through a")
        XCTAssertEqual(Set(store.jumpServerChoices(for: a.id).map(\.machine.name)), ["b", "vnc"])
        XCTAssertEqual(choosable(b.id), ["a", "vnc"])
        XCTAssertEqual(choosable(nil), ["a", "b", "vnc"])

        var looping = a
        looping.transport = .proxyJump
        looping.proxyJumpMachineID = b.id
        XCTAssertFalse(store.save(looping))
        XCTAssertNotNil(store.problem(saving: looping))

        // The loop arrives from elsewhere.
        try storage.save(looping)
        store.reload()
        var used = try XCTUnwrap(store.machine(a.id))
        used.lastBanner = "hello"
        XCTAssertTrue(store.save(used))
        XCTAssertEqual(store.machine(a.id)?.lastBanner, "hello")
    }

    func testLoopsAreCutWhereTheyClose() {
        var a = RDMachine(remoteAddress: "a", remotePort: "22", name: "a")
        var b = RDMachine(remoteAddress: "b", remotePort: "22", name: "b")
        var c = RDMachine(remoteAddress: "c", remotePort: "22", name: "c")
        a.transport = .proxyJump
        a.proxyJumpMachineID = b.id
        b.transport = .proxyJump
        b.proxyJumpMachineID = a.id
        c.transport = .proxyJump
        c.proxyJumpMachineID = a.id
        let fixed = RDMachine.breakingProxyJumpLoops([a, b, c])
        for machine in fixed {
            XCTAssertNoThrow(try machine.proxyJumpChain { id in fixed.first { $0.id == id } })
        }
        XCTAssertEqual(fixed.filter { $0.transport == .proxyJump }.count, 2, "one link is cut")
    }

    /// Lookups off the main actor (made from view bodies too) read the
    /// shared store's copy, not the database and the keychain.
    @MainActor
    func testWorkerLookupsFollowTheStore() {
        let store = test.store()
        store.publishesWorkerSnapshot = true
        defer { RayonStore.workerSnapshot.withLock { $0 = WorkerSnapshot() } }
        let identity = RDIdentity(username: "root", password: "pw")
        store.save(identity)
        let machine = RDMachine(remoteAddress: "a", remotePort: "22", name: "a", associatedIdentity: identity.id)
        store.save(machine)
        XCTAssertEqual(RayonStore.workerMachine(for: machine.id)?.name, "a")
        XCTAssertEqual(RayonStore.workerAssociatedIdentity(for: machine)?.password, "pw")
        XCTAssertEqual(RayonStore.workerIdentitiesForAutoAuth.map(\.id), [identity.id])
        store.deleteMachines([machine.id])
        XCTAssertNil(RayonStore.workerMachine(for: machine.id))
    }

    /// A save here and a merge of another device's version never
    /// interleave: while one holds the write lock the other waits, so
    /// neither decides on a row the other is about to replace. The lock is
    /// held here, and both are shown to wait for it.
    func testSavesAndMergesDoNotOverwriteEachOther() throws {
        let original = try storage.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "v0"))
        var theirs = original
        theirs.name = "there"
        theirs.modified = original.modified.addingTimeInterval(60)
        var mine = original
        mine.name = "here"
        let storage = storage
        let (merged, saved) = (DispatchGroup(), DispatchGroup())
        merged.enter()
        saved.enter()
        storage.writes.withLock { _ in
            DispatchQueue.global().async { [theirs] in
                _ = try? storage.mergeRemote(theirs)
                merged.leave()
            }
            DispatchQueue.global().async { [mine] in
                _ = try? storage.save(mine)
                saved.leave()
            }
            XCTAssertEqual(merged.wait(timeout: .now() + 0.3), .timedOut, "the merge waits for the lock")
            XCTAssertEqual(saved.wait(timeout: .now() + 0.3), .timedOut, "the save waits for the lock")
            XCTAssertEqual(storage.record(RDMachine.self, id: original.id)?.name, "v0")
        }
        merged.wait()
        saved.wait()
        // Either order is a whole one: the save after the merge wins and is
        // queued; the merge after the save wins and nothing is left to send.
        switch storage.record(RDMachine.self, id: original.id)?.name {
        case "here": XCTAssertEqual(storage.pendingUploads().map(\.objectId), [original.id])
        case "there": XCTAssertEqual(storage.pendingUploads().map(\.objectId), [])
        case let name: XCTFail("unexpected \(String(describing: name))")
        }
    }

    /// A database a newer Rayon wrote is left where it is, untouched, and
    /// the reason is given; a damaged one is moved aside.
    func testANewerDatabaseIsLeftAlone() throws {
        let url = test.directory.appendingPathComponent("newer/database.db")
        let newer = try RayonStorage(databaseURL: url, secrets: test.secrets)
        try newer.save(RDMachine(remoteAddress: "a", remotePort: "22", name: "a"))
        try newer.db.exec(StatementPragma().pragma(.userVersion).to(999))
        newer.close()

        let opened = RayonStorage.open(at: url, secrets: test.secrets)
        defer { opened.close() }
        XCTAssertNotNil(opened.openProblem)
        XCTAssertNotEqual(opened.databaseURL, url)
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertFalse(files.contains { $0.contains("unreadable") })
        let check = Database(at: url.path)
        defer { check.close() }
        XCTAssertEqual(try check.getValue(from: StatementPragma().pragma(.userVersion))?.intValue, 999)
    }

    /// Only a damaged database is moved aside. One that cannot be opened
    /// for another reason (here permissions; on iOS, protected data before
    /// the first unlock) is left where it is, says so, takes no writes, and
    /// opens once it can.
    func testOnlyADamagedDatabaseIsMovedAside() throws {
        let damaged = test.directory.appendingPathComponent("damaged/database.db")
        try FileManager.default.createDirectory(at: damaged.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8192).write(to: damaged)
        let fresh = RayonStorage.open(at: damaged, secrets: test.secrets)
        XCTAssertNil(fresh.openProblem)
        XCTAssertNoThrow(try fresh.save(RDSnippet(name: "new", code: "true")))
        fresh.close()
        let names = try FileManager.default.contentsOfDirectory(atPath: damaged.deletingLastPathComponent().path)
        XCTAssertTrue(names.contains { $0.contains("unreadable") })

        let url = test.directory.appendingPathComponent("locked/database.db")
        let first = try RayonStorage(databaseURL: url, secrets: test.secrets)
        let snippet = try first.save(RDSnippet(name: "uptime", code: "uptime"))
        first.close()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let locked = RayonStorage.open(at: url, secrets: test.secrets)
        defer { locked.close() }
        XCTAssertEqual(locked.databaseURL, url)
        XCTAssertNotNil(locked.openProblem)
        XCTAssertEqual(locked.records(RDSnippet.self), [])
        XCTAssertThrowsError(try locked.save(RDSnippet(name: "lost", code: "true")))
        let lockedNames = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertFalse(lockedNames.contains { $0.contains("unreadable") })

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let opened = expectation(forNotification: RayonStorage.didOpen, object: locked)
        XCTAssertEqual(locked.records(RDSnippet.self).map(\.id), [snippet.id])
        wait(for: [opened], timeout: 1)
        XCTAssertNil(locked.openProblem)
        XCTAssertNoThrow(try locked.save(RDSnippet(name: "later", code: "true")))
    }

    /// A database from before host keys knew which release saved them
    /// keeps its keys, none of them taken for one an old release saved.
    func testKnownHostsGainTheirLegacyMarker() throws {
        struct V4KnownHost: TableCodable {
            var name = "[a]:22"
            var type = "ecdsa-sha2-nistp256"
            var key = Data([1])
            var added = Date()
            enum CodingKeys: String, CodingTableKey {
                typealias Root = V4KnownHost
                static let objectRelationalMapping = TableBinding(CodingKeys.self) {
                    BindColumnConstraint(name, isPrimary: true)
                }

                case name, type, key, added
            }
        }
        let url = test.directory.appendingPathComponent("v4/database.db")
        let old = try RayonStorage(databaseURL: url, secrets: test.secrets)
        try old.db.drop(table: KnownHostRecord.tableName)
        try old.db.create(table: KnownHostRecord.tableName, of: V4KnownHost.self)
        try old.db.insert(V4KnownHost(), intoTable: KnownHostRecord.tableName)
        try old.db.exec(StatementPragma().pragma(.userVersion).to(4))
        old.close()

        let reopened = try RayonStorage(databaseURL: url, secrets: test.secrets)
        defer { reopened.close() }
        let host = try XCTUnwrap(reopened.knownHost(named: "[a]:22"))
        XCTAssertEqual(host.key, Data([1]))
        XCTAssertFalse(host.legacy)
    }
}
