//
//  LegacySettingsImportTests.swift
//  RayonModuleTests
//
//  2.8's settings, under their old keys, arrive under the new ones.
//

import ConfigurableKit
@testable import RayonModule
import XCTest

final class LegacySettingsImportTests: XCTestCase {
    private var defaults: UserDefaults!
    private var storage: UserDefaultKeyValueStorage!

    override func setUp() {
        defaults = UserDefaults(suiteName: "rayon-tests-\(UUID().uuidString)")
        storage = UserDefaultKeyValueStorage(suite: defaults)
    }

    private func value<Value>(_ key: SettingKey<Value>) -> Value? {
        ConfigurableKit.value(forKey: key.key, storage: storage)
    }

    func testOldSettingsMoveToTheirNewKeys() {
        let server = UUID()
        let old: [String: Any] = [
            "appearance": "dark",
            "reducedViewEffects": true,
            "openInterfaceAutomatically": false,
            "disableConformation": true,
            "storeRecent": false,
            "maxRecentRecordCount": 20,
            "saveTemporarySession": false,
            "timeout": 12,
            "terminfo.install": false,
            "monitorInterval": 30,
            "machineRedacted": 2,
            "terminalFontSize": 17,
            "terminalCopyOnSelect": false,
            "terminalClipboardSharing": false,
            "editor.wrapsLines": true,
            "remoteDesktop.touchMode": "direct",
            "remoteDesktop.gestureHintsShown": 3,
            "menubarMachines": [server.uuidString],
            "sync.enabled": true,
            "sync.identities": false,
        ]
        for (key, value) in old {
            defaults.set(value, forKey: "me.mizorewww.rayon." + key)
        }

        XCTAssertEqual(LegacySettingsImport.run(defaults: defaults, storage: storage), old.count)
        XCTAssertEqual(LegacySettingsImport.run(defaults: defaults, storage: storage), 0, "once")

        XCTAssertEqual(value(AppSettings.appearance), .dark)
        XCTAssertEqual(value(AppSettings.animatesHome), false)
        XCTAssertEqual(value(AppSettings.showsSessionOnConnect), false)
        XCTAssertEqual(value(AppSettings.confirmsClosingSession), false)
        XCTAssertEqual(value(AppSettings.remembersRecent), false)
        XCTAssertEqual(value(AppSettings.recentLimit), 20)
        XCTAssertEqual(value(AppSettings.remembersRecentCommands), false)
        XCTAssertEqual(value(AppSettings.connectionTimeout), 12)
        XCTAssertEqual(value(AppSettings.installsTerminfo), false)
        XCTAssertEqual(value(AppSettings.monitorInterval), 30)
        XCTAssertEqual(value(AppSettings.serverRedaction), RDMachine.RedactedLevel(rawValue: 2))
        XCTAssertEqual(value(AppSettings.terminalFontSize), 17)
        XCTAssertEqual(value(AppSettings.terminalCopiesOnSelect), false)
        XCTAssertEqual(value(AppSettings.terminalSharesClipboard), false)
        XCTAssertEqual(value(AppSettings.editorWrapsLines), true)
        XCTAssertEqual(value(AppSettings.remoteDesktopTouchMode), .direct)
        XCTAssertEqual(value(AppSettings.remoteDesktopGestureHintsShown), 3)
        XCTAssertEqual(value(AppSettings.menuBarServers), [server])
        XCTAssertEqual(value(AppSettings.syncEnabled), true)
        XCTAssertEqual(value(AppSettings.syncsIdentities), false)
        // Not set before: still unset, so it keeps its default.
        XCTAssertNil(value(AppSettings.syncsServers))
        for key in old.keys {
            XCTAssertNil(defaults.object(forKey: "me.mizorewww.rayon." + key), key)
        }
    }

    /// 2.8's single "sync settings" switch, turned off, keeps both the app
    /// and the terminal settings out of iCloud.
    func testTheSettingsSyncSwitchCoversBothScopes() {
        defaults.set(true, forKey: "me.mizorewww.rayon.sync.enabled")
        defaults.set(false, forKey: "me.mizorewww.rayon.sync.settings")

        LegacySettingsImport.run(defaults: defaults, storage: storage)

        XCTAssertEqual(value(AppSettings.syncEnabled), true)
        XCTAssertEqual(value(AppSettings.syncsAppSettings), false)
        XCTAssertEqual(value(AppSettings.syncsTerminalSettings), false)
        XCTAssertNil(defaults.object(forKey: "me.mizorewww.rayon.sync.settings"))
    }

    /// A setting already under its new key is not overwritten, and the old
    /// key goes anyway, so a later launch changes nothing.
    func testANewValueWinsAndTheOldKeyGoes() {
        ConfigurableKit.set(value: 9, forKey: AppSettings.connectionTimeout.key, storage: storage)
        defaults.set(30, forKey: "me.mizorewww.rayon.timeout")

        XCTAssertEqual(LegacySettingsImport.run(defaults: defaults, storage: storage), 0, "nothing moved")

        XCTAssertEqual(value(AppSettings.connectionTimeout), 9)
        XCTAssertNil(defaults.object(forKey: "me.mizorewww.rayon.timeout"))
    }
}
