//
//  AppSettingsSyncTests.swift
//  RayonModuleTests
//
//  The app settings through iCloud sync, without CloudKit: which travel,
//  and how another device's settings and these are merged.
//

import ConfigurableKit
@testable import RayonModule
import XCTest

@MainActor
final class AppSettingsSyncTests: XCTestCase {
    private var test: TestStorage!
    private var storage: RayonStorage { test.storage }
    private var settings: UserDefaultKeyValueStorage!

    private let timeout = AppSettings.connectionTimeout.key
    private let animatesHome = AppSettings.animatesHome.key
    private let appearance = AppSettings.appearance.key
    private let remembersRecent = AppSettings.remembersRecent.key
    private let redaction = AppSettings.serverRedaction.key

    override func setUpWithError() throws {
        test = try TestStorage()
        settings = UserDefaultKeyValueStorage(suite: UserDefaults(suiteName: "rayon-tests-\(UUID().uuidString)")!)
    }

    override func tearDown() {
        test = nil
        settings = nil
    }

    private func sync() -> AppSettingsSync {
        AppSettingsSync(storage: storage, settings: settings)
    }

    private func set(_ value: some Codable, _ key: String) {
        ConfigurableKit.set(value: value, forKey: key, storage: settings)
    }

    private func value<T: Codable>(_ key: String) -> T? {
        ConfigurableKit.value(forKey: key, storage: settings)
    }

    private var record: RDAppSettings? {
        storage.record(RDAppSettings.self, id: RDAppSettings.recordID)
    }

    func testTheSyncedKeysAreTheSettingsDeclaredSynced() {
        XCTAssertTrue(AppSettings.syncedKeys.contains(timeout))
        XCTAssertFalse(AppSettings.syncedKeys.contains(AppSettings.terminalFontSize.key))
        XCTAssertFalse(AppSettings.syncedKeys.contains(AppSettings.syncEnabled.key))
        XCTAssertFalse(AppSettings.syncedKeys.contains(AppSettings.menuBarServers.key))
        XCTAssertEqual(Set(AppSettings.all.map(\.key)).count, AppSettings.all.count, "a key is declared twice")
    }

    func testOnlySettingsThatTravelAreWritten() {
        set(12, timeout)
        set(false, animatesHome)
        set(Appearance.dark, appearance)
        set(RDMachine.RedactedLevel.all, redaction)
        set(20, AppSettings.terminalFontSize.key)
        set([UUID()], AppSettings.menuBarServers.key)
        sync().start()
        XCTAssertEqual(record?.values, [
            timeout: .int(12),
            animatesHome: .bool(false),
            appearance: .string("dark"),
            redaction: .int(2),
        ])
        // Settings nobody changed since sync came are older than any other device's.
        XCTAssertEqual(record?.modified, Date(timeIntervalSince1970: 0))
    }

    func testDefaultsAloneWriteNothing() {
        set(20, AppSettings.terminalFontSize.key)
        sync().start()
        XCTAssertNil(record)
    }

    func testChangesHereAndFromAnotherDevice() throws {
        set(12, timeout)
        let sync = sync()
        sync.start()

        // Changed here: written, as now.
        set(false, remembersRecent)
        sync.push()
        XCTAssertEqual(record?.values[remembersRecent], .bool(false))
        XCTAssertGreaterThan(try XCTUnwrap(record?.modified), Date(timeIntervalSinceNow: -60))

        // Another device's later settings: applied, and one they lack reset.
        var remote = RDAppSettings(entries: [timeout: .int(30), redaction: .int(2)])
        remote.modified = Date().addingTimeInterval(60)
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        sync.pull()
        XCTAssertEqual(value(timeout) as Int?, 30)
        XCTAssertEqual(value(redaction) as RDMachine.RedactedLevel?, .all)
        XCTAssertNil(settings.value(forKey: remembersRecent))

        // Applying them is not a change here.
        sync.push()
        XCTAssertEqual(record?.modified.millisecondsSince1970, remote.modified.millisecondsSince1970)
    }

    /// Another device's settings are merged into the record on the sync
    /// actor and applied here a moment later. A change noticed in between
    /// (a window's frame saved, say) does not write what is here over them.
    func testAMergedRecordIsNotRevertedBeforeItIsApplied() throws {
        set(12, timeout)
        let sync = sync()
        sync.start()

        var remote = RDAppSettings(entries: [timeout: .int(30)])
        remote.modified = Date().addingTimeInterval(60).wholeMilliseconds
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        set("0 0 800 600", "window.frame")
        sync.push()
        XCTAssertEqual(record?.values, [timeout: .int(30)])
        XCTAssertEqual(record?.modified, remote.modified)
        XCTAssertEqual(value(timeout) as Int?, 30)

        sync.pull()
        XCTAssertEqual(record?.modified, remote.modified)
        XCTAssertEqual(value(timeout) as Int?, 30)
    }

    /// A change here and another device's to another setting, crossing:
    /// both stay.
    func testCrossingChangesToOtherSettingsBothStay() throws {
        set(12, timeout)
        set(true, remembersRecent)
        let sync = sync()
        sync.start()

        var remote = RDAppSettings(entries: [timeout: .int(30), remembersRecent: .bool(true)])
        remote.modified = Date().addingTimeInterval(60).wholeMilliseconds
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        set(false, remembersRecent)
        sync.push()
        XCTAssertEqual(record?.values, [timeout: .int(30), remembersRecent: .bool(false)])
        XCTAssertEqual(value(timeout) as Int?, 30)
        XCTAssertEqual(value(remembersRecent) as Bool?, false)
    }

    func testAtLaunchTheRecordWins() {
        try? storage.save(RDAppSettings(entries: [timeout: .int(9)]))
        set(12, timeout)
        sync().start()
        XCTAssertEqual(value(timeout) as Int?, 9)
    }

    func testTheScopeDecides() {
        var preferences = CloudSyncPreferences(isOn: true)
        XCTAssertTrue(preferences.syncs(table: RDAppSettings.tableName))
        preferences.appSettings = false
        XCTAssertFalse(preferences.syncs(table: RDAppSettings.tableName))
    }
}
