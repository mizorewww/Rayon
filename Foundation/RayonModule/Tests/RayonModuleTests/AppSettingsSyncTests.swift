//
//  AppSettingsSyncTests.swift
//  RayonModuleTests
//
//  The app settings through iCloud sync, without CloudKit: which travel,
//  and how another device's settings and these are merged.
//

@testable import RayonModule
import XCTest

@MainActor
final class AppSettingsSyncTests: XCTestCase {
    private var test: TestStorage!
    private var storage: RayonStorage { test.storage }
    private var defaults: UserDefaults!
    private var applied = 0

    override func setUpWithError() throws {
        test = try TestStorage()
        defaults = UserDefaults(suiteName: "rayon-tests-\(UUID().uuidString)")!
        applied = 0
    }

    override func tearDown() {
        test = nil
        defaults = nil
    }

    private func sync() -> AppSettingsSync {
        AppSettingsSync(storage: storage, defaults: defaults) { [weak self] in self?.applied += 1 }
    }

    private var record: RDAppSettings? {
        storage.record(RDAppSettings.self, id: RDAppSettings.recordID)
    }

    func testOnlySettingsThatTravelAreWritten() {
        defaults.set(12, forKey: RayonStore.Key.timeout)
        defaults.set(true, forKey: RayonStore.Key.reducedViewEffects)
        defaults.set("dark", forKey: "me.mizorewww.rayon.appearance")
        defaults.set(20, forKey: RayonStore.Key.terminalFontSize)
        defaults.set(true, forKey: "me.mizorewww.rayon.menubarMachines")
        sync().start()
        XCTAssertEqual(record?.values, [
            RayonStore.Key.timeout: .int(12),
            RayonStore.Key.reducedViewEffects: .bool(true),
            "me.mizorewww.rayon.appearance": .string("dark"),
        ])
        // Settings nobody changed since sync came are older than any other device's.
        XCTAssertEqual(record?.modified, Date(timeIntervalSince1970: 0))
    }

    func testDefaultsAloneWriteNothing() {
        defaults.set(20, forKey: RayonStore.Key.terminalFontSize)
        sync().start()
        XCTAssertNil(record)
    }

    func testChangesHereAndFromAnotherDevice() throws {
        defaults.set(12, forKey: RayonStore.Key.timeout)
        let sync = sync()
        sync.start()

        // Changed here: written, as now.
        defaults.set(false, forKey: RayonStore.Key.storeRecent)
        sync.push()
        XCTAssertEqual(record?.values[RayonStore.Key.storeRecent], .bool(false))
        XCTAssertGreaterThan(try XCTUnwrap(record?.modified), Date(timeIntervalSinceNow: -60))

        // Another device's later settings: applied, and one they lack reset.
        var remote = RDAppSettings(entries: [RayonStore.Key.timeout: .int(30), RayonStore.Key.machineRedacted: .int(2)])
        remote.modified = Date().addingTimeInterval(60)
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        sync.pull()
        XCTAssertEqual(defaults.integer(forKey: RayonStore.Key.timeout), 30)
        XCTAssertEqual(defaults.integer(forKey: RayonStore.Key.machineRedacted), 2)
        XCTAssertNil(defaults.object(forKey: RayonStore.Key.storeRecent))
        XCTAssertEqual(applied, 1)

        // Applying them is not a change here.
        sync.push()
        XCTAssertEqual(record?.modified.millisecondsSince1970, remote.modified.millisecondsSince1970)
    }

    func testAtLaunchTheRecordWins() {
        try? storage.save(RDAppSettings(entries: [RayonStore.Key.timeout: .int(9)]))
        defaults.set(12, forKey: RayonStore.Key.timeout)
        sync().start()
        XCTAssertEqual(defaults.integer(forKey: RayonStore.Key.timeout), 9)
    }

    func testTheScopeDecides() {
        var preferences = CloudSyncPreferences(isOn: true)
        XCTAssertTrue(preferences.syncs(table: RDAppSettings.tableName))
        preferences.appSettings = false
        XCTAssertFalse(preferences.syncs(table: RDAppSettings.tableName))
    }
}
