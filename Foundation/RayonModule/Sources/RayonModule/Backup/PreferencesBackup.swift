//
//  PreferencesBackup.swift
//  RayonModule
//
//  A backup of the app's preferences, apart from the data: the Rayon
//  settings in the user defaults, without what belongs to this device or
//  this install, and the terminal's config.ghostty.
//

import Foundation
import RayonTerminal

public enum PreferencesBackup {
    public static let fileExtension = "rayonsettings"
    static let preferencesFile = "preferences.plist"
    static let terminalFile = "config.ghostty"

    /// Rayon's own settings: its prefix, and the license agreement.
    static func isPreference(_ key: String) -> Bool {
        guard key.hasPrefix("me.mizorewww.rayon.") else { return false }
        let deviceBound = [
            "me.mizorewww.rayon.storage.",
            "me.mizorewww.rayon.sync.",
            "me.mizorewww.rayon.menubarMachines",
            "me.mizorewww.rayon.uuremote.",
        ]
        return !deviceBound.contains { key.hasPrefix($0) }
    }

    @MainActor
    public static func export(
        from defaults: UserDefaults = .standard,
        terminal: TerminalSettings = .shared,
        to url: URL
    ) throws {
        let values = defaults.dictionaryRepresentation().filter { isPreference($0.key) }
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try BackupArchive.write(
            [preferencesFile: data, terminalFile: Data(terminal.contents.utf8)],
            kind: .preferences, includesSecrets: false, password: nil, to: url
        )
    }

    /// Reads the preferences at `url`, sets them and applies the terminal
    /// settings in it; returns how many preferences. A backup from before
    /// config.ghostty carries the terminal settings among the preferences.
    @MainActor @discardableResult
    public static func restore(
        from url: URL,
        into defaults: UserDefaults = .standard,
        terminal: TerminalSettings = .shared
    ) throws -> Int {
        let (_, files) = try BackupArchive.read(url, kind: .preferences, password: nil)
        guard let data = files[preferencesFile],
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw BackupError.damaged("it has no preferences") }
        if let file = files[terminalFile] {
            guard let text = String(data: file, encoding: .utf8) else { throw BackupError.damaged("its terminal settings are not text") }
            try terminal.load(text)
        }
        let accepted = values.filter { isPreference($0.key) }
        for (key, value) in accepted {
            defaults.set(value, forKey: key)
        }
        if files[terminalFile] == nil {
            try terminal.loadLegacy(from: defaults)
        }
        return accepted.count
    }
}

public extension RayonStore {
    /// Reads the preferences again after they were restored.
    func reloadPreferences(from defaults: UserDefaults = .standard) {
        storeRecent = Self.bool(Key.storeRecent, default: true, in: defaults)
        saveTemporarySession = Self.bool(Key.saveTemporarySession, default: true, in: defaults)
        let savedTimeout = Self.int(Key.timeout, default: 5, in: defaults)
        timeout = savedTimeout > 0 ? savedTimeout : 5
        reducedViewEffects = Self.bool(Key.reducedViewEffects, default: false, in: defaults)
        disableConformation = Self.bool(Key.disableConformation, default: false, in: defaults)
        monitorInterval = Self.int(Key.monitorInterval, default: 3, in: defaults)
        terminalFontSize = Self.int(Key.terminalFontSize, default: 14, in: defaults)
        terminalCopyOnSelect = Self.bool(Key.terminalCopyOnSelect, default: true, in: defaults)
        terminalClipboardSharing = Self.bool(Key.terminalClipboardSharing, default: true, in: defaults)
        maxRecentRecordCount = Self.int(Key.maxRecentRecordCount, default: 8, in: defaults)
        openInterfaceAutomatically = Self.bool(Key.openInterfaceAutomatically, default: true, in: defaults)
        machineRedacted = RDMachine.RedactedLevel(rawValue: defaults.integer(forKey: Key.machineRedacted)) ?? .none
    }
}
