//
//  LegacySettingsImport.swift
//  RayonModule
//
//  Moves the settings 2.8 kept under its own UserDefaults keys to their
//  `AppSettings` keys, on the first launch after the update, so nobody
//  loses them. A value moves only when the new key is not set yet; the old
//  key is removed either way, so it runs once.
//

import ConfigurableKit
import Foundation

public enum LegacySettingsImport {
    /// Returns how many of 2.8's settings it moved: 0 once they have been.
    @discardableResult
    public static func run(defaults: UserDefaults = .standard, storage: KeyValueStorage = ConfigurableKit.storage) -> Int {
        var moved = 0
        func move<Value>(_ old: String, to key: SettingKey<Value>, _ convert: (Any) -> Value?) {
            move(old, to: [key], convert)
        }
        func move<Value>(_ old: String, to keys: [SettingKey<Value>], _ convert: (Any) -> Value?) {
            let old = "me.mizorewww.rayon." + old
            guard let object = defaults.object(forKey: old) else { return }
            var took = false
            for key in keys where storage.value(forKey: key.key) == nil {
                if let value = convert(object) {
                    ConfigurableKit.set(value: value, forKey: key.key, storage: storage)
                    took = true
                }
            }
            if took { moved += 1 }
            defaults.removeObject(forKey: old)
        }
        let bool = { (object: Any) in (object as? NSNumber)?.boolValue }
        let int = { (object: Any) in (object as? NSNumber)?.intValue }
        let inverted = { (object: Any) in (object as? NSNumber).map { !$0.boolValue } }

        move("appearance", to: AppSettings.appearance) { ($0 as? String).flatMap(Appearance.init(rawValue:)) }
        move("reducedViewEffects", to: AppSettings.animatesHome, inverted)
        move("openInterfaceAutomatically", to: AppSettings.showsSessionOnConnect, bool)
        move("disableConformation", to: AppSettings.confirmsClosingSession, inverted)
        move("storeRecent", to: AppSettings.remembersRecent, bool)
        move("maxRecentRecordCount", to: AppSettings.recentLimit, int)
        move("saveTemporarySession", to: AppSettings.remembersRecentCommands, bool)
        move("timeout", to: AppSettings.connectionTimeout, int)
        move("terminfo.install", to: AppSettings.installsTerminfo, bool)
        move("monitorInterval", to: AppSettings.monitorInterval, int)
        move("machineRedacted", to: AppSettings.serverRedaction) { int($0).flatMap(RDMachine.RedactedLevel.init(rawValue:)) }
        move("terminalFontSize", to: AppSettings.terminalFontSize, int)
        move("terminalCopyOnSelect", to: AppSettings.terminalCopiesOnSelect, bool)
        move("terminalClipboardSharing", to: AppSettings.terminalSharesClipboard, bool)
        move("editor.wrapsLines", to: AppSettings.editorWrapsLines, bool)
        move("remoteDesktop.touchMode", to: AppSettings.remoteDesktopTouchMode) {
            ($0 as? String).flatMap(RemoteDesktopTouchMode.init(rawValue:))
        }
        move("remoteDesktop.gestureHintsShown", to: AppSettings.remoteDesktopGestureHintsShown, int)
        move("menubarMachines", to: AppSettings.menuBarServers) { ($0 as? [String])?.compactMap(UUID.init(uuidString:)) }
        move("sync.enabled", to: AppSettings.syncEnabled, bool)
        move("sync.servers", to: AppSettings.syncsServers, bool)
        move("sync.identities", to: AppSettings.syncsIdentities, bool)
        move("sync.snippets", to: AppSettings.syncsSnippets, bool)
        move("sync.portForwards", to: AppSettings.syncsPortForwards, bool)
        // 2.8 had one switch for all settings; it now covers two.
        move("sync.settings", to: [AppSettings.syncsAppSettings, AppSettings.syncsTerminalSettings], bool)
        return moved
    }
}
