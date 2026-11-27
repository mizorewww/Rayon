//
//  TerminalSettingsSyncTests.swift
//  RayonModuleTests
//
//  The terminal settings through iCloud sync, without CloudKit: which keys
//  travel, and how another device's settings and these are merged.
//

import CloudKit
@testable import RayonModule
import RayonTerminal
import XCTest

@MainActor
final class TerminalSettingsSyncTests: XCTestCase {
    private var test: TestStorage!
    private var storage: RayonStorage { test.storage }

    override func setUp() async throws {
        test = try TestStorage()
    }

    override func tearDown() async throws {
        // The scratch settings applied themselves to the shared terminal configuration.
        try? TerminalSettings.shared.load(TerminalSettings.shared.applied)
        test = nil
    }

    /// Settings of their own, moved from `text` as an earlier release's
    /// config.ghostty, like a first launch after the update.
    private func settings(_ text: String) throws -> TerminalSettings {
        let folder = test.directory.appending(path: "terminal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "config.ghostty")
        try Data(text.utf8).write(to: url)
        return TerminalSettings(fileURL: folder.appending(path: "terminal-settings.json"), importing: url)
    }

    private var record: RDTerminalSettings? {
        storage.record(RDTerminalSettings.self, id: RDTerminalSettings.recordID)
    }

    func testOnlyKeysThatTravelAreWritten() throws {
        let local = try settings("# mine\nfont-size = 18\nwindow-padding-y = 6\nbackground = #101010\nnot-a-ghostty-key = 1\n")
        let sync = TerminalSettingsSync(storage: storage, settings: local)
        sync.start()
        XCTAssertEqual(record?.values, ["background": ["#101010"]])
        XCTAssertEqual(storage.pendingUploads().map(\.tableName), [RDTerminalSettings.tableName])

        // A first record is older than any other device's.
        XCTAssertEqual(record?.modified, Date(timeIntervalSince1970: 0))
    }

    /// Settings moved out of config.ghostty at launch, on a device that
    /// updates late: they are not newer than a change made since on another
    /// device.
    func testImportedSettingsAreNotNewerThanAnotherDevicesChange() throws {
        let local = try settings("background = #202020\n")
        XCTAssertEqual(TerminalConfigurationSync.entries(of: local), ["background": ["#202020"]])
        TerminalSettingsSync(storage: storage, settings: local).start()

        var remote = RDTerminalSettings(entries: ["background": ["#ffffff"]])
        remote.modified = Date().addingTimeInterval(-3600).wholeMilliseconds
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        XCTAssertEqual(record?.values, ["background": ["#ffffff"]])
    }

    func testDefaultsAloneWriteNothing() throws {
        TerminalSettingsSync(storage: storage, settings: try settings("font-size = 20\n")).start()
        XCTAssertNil(record)
    }

    func testChangesHereAndFromAnotherDevice() throws {
        let local = try settings("font-size = 18\nbackground = #101010\n")
        let sync = TerminalSettingsSync(storage: storage, settings: local)
        sync.start()

        // Another device's later settings replace these, except the font size.
        var remote = RDTerminalSettings(entries: ["foreground": ["#fafafa"], "font-size": ["40"]])
        remote.modified = Date().addingTimeInterval(60).wholeMilliseconds
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        NotificationCenter.default.post(name: RayonStorage.didMergeRemoteChanges, object: nil)
        XCTAssertEqual(local.applied, ["font-size": ["18"], "foreground": ["#fafafa"]])

        // An older one loses: what is here goes out again.
        var stale = RDTerminalSettings(entries: ["background": ["#000000"]])
        stale.modified = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(try storage.mergeRemote(stale), .keptLocal)
        XCTAssertEqual(record?.values, remote.values)

        // A change here is written to the record.
        TerminalConfigurationSync.adopt(["foreground": ["#fafafa"], "cursor-color": ["#ff0000"]], into: local)
        XCTAssertEqual(record?.values, ["foreground": ["#fafafa"], "cursor-color": ["#ff0000"]])
    }

    /// Another device's settings merged into the record before they are
    /// applied here, and a change to this device's own keys in between:
    /// what is here is not written over them.
    func testAMergedRecordIsNotRevertedBeforeItIsApplied() throws {
        let local = try settings("font-size = 18\nbackground = #101010\n")
        let sync = TerminalSettingsSync(storage: storage, settings: local)
        sync.start()

        var remote = RDTerminalSettings(entries: ["background": ["#202020"]])
        remote.modified = Date().addingTimeInterval(60).wholeMilliseconds
        XCTAssertEqual(try storage.mergeRemote(remote), .tookRemote)
        try local.load(["font-size": ["20"], "background": ["#101010"]])
        sync.push()
        XCTAssertEqual(record?.values, ["background": ["#202020"]])
        XCTAssertEqual(record?.modified, remote.modified)
        XCTAssertEqual(local.applied, ["font-size": ["20"], "background": ["#202020"]])
    }

    /// A change on one device reaches another through the record, as CloudKit
    /// carries it, and is saved there; that device's font size stays its own.
    func testAChangeTravelsToAnotherDevice() async throws {
        let mine = try settings("font-size = 18\nbackground = #101010\n")
        let mySync = TerminalSettingsSync(storage: storage, settings: mine)
        mySync.start()
        try mine.load(["font-size": ["18"], "background": ["#101010"], "keybind": ["clear", "ctrl+k=ignore"]])
        let sent = try XCTUnwrap(record)
        XCTAssertEqual(sent.values, ["background": ["#101010"], "keybind": ["clear", "ctrl+k=ignore"]])

        let other = try TestStorage()
        let theirs = try settings("font-size = 30\n")
        let theirSync = TerminalSettingsSync(storage: other.storage, settings: theirs)
        theirSync.start()
        var arrived = try XCTUnwrap(CloudRecordCoding.decode(CloudRecordCoding.ckRecord(for: sent, systemFields: nil)) as? RDTerminalSettings)
        arrived.modified = Date().addingTimeInterval(60).wholeMilliseconds
        XCTAssertEqual(try other.storage.mergeRemote(arrived), .tookRemote)
        NotificationCenter.default.post(name: RayonStorage.didMergeRemoteChanges, object: nil)
        XCTAssertEqual(theirs.applied, ["font-size": ["30"], "background": ["#101010"], "keybind": ["clear", "ctrl+k=ignore"]])

        await theirs.saved()
        XCTAssertEqual(TerminalSettings(fileURL: theirs.fileURL, importing: nil).applied, theirs.applied)
        withExtendedLifetime((mySync, theirSync)) {}
    }

    func testTheRecordRoundTripsThroughCloudKit() throws {
        var settings = RDTerminalSettings(entries: ["keybind": ["clear", "ctrl+k=ignore"], "theme": ["light:A,dark:B"]])
        settings.modified = Date(timeIntervalSince1970: 1_700_000_000)
        let ck = try CloudRecordCoding.ckRecord(for: settings, systemFields: nil)
        XCTAssertEqual(ck.recordType, RDTerminalSettings.tableName)
        XCTAssertEqual(try CloudRecordCoding.decode(ck) as? RDTerminalSettings, settings)
        XCTAssertTrue(CloudSyncPreferences(isOn: true).syncs(table: RDTerminalSettings.tableName))
        XCTAssertFalse(CloudSyncPreferences(isOn: true, terminalSettings: false).syncs(table: RDTerminalSettings.tableName))
    }
}
