//
//  PreferencesBackup.swift
//  RayonModule
//
//  A backup of the app's settings, apart from the data: every setting
//  `AppSettings` declares that may leave the device, as ConfigurableKit
//  stores it, and the terminal's config.ghostty.
//

import ConfigurableKit
import Foundation
import RayonTerminal

public enum PreferencesBackup {
    public static let fileExtension = "rayonsettings"
    static let preferencesFile = "preferences.plist"
    static let terminalFile = "config.ghostty"

    /// The keys a backup carries: all but what never leaves the device.
    static let keys: Set<String> = Set(AppSettings.all.filter { $0.scope != .deviceLocal }.map(\.key))

    @MainActor
    public static func export(
        from settings: KeyValueStorage = ConfigurableKit.storage,
        terminal: TerminalSettings = .shared,
        to url: URL
    ) throws {
        var values: [String: Data] = [:]
        for key in keys {
            values[key] = settings.value(forKey: key)
        }
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try BackupArchive.write(
            [preferencesFile: data, terminalFile: Data(terminal.contents.utf8)],
            kind: .preferences, includesSecrets: false, password: nil, to: url
        )
    }

    /// Reads the settings at `url`, sets them (a setting the backup lacks
    /// is reset) and applies the terminal settings in it; returns how many
    /// settings it set.
    @MainActor @discardableResult
    public static func restore(
        from url: URL,
        into settings: KeyValueStorage = ConfigurableKit.storage,
        terminal: TerminalSettings = .shared
    ) throws -> Int {
        let (_, files) = try BackupArchive.read(url, kind: .preferences, password: nil)
        guard let data = files[preferencesFile],
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw BackupError.damaged("it has no settings") }
        // Older backups kept other keys, and the terminal among them.
        guard let file = files[terminalFile] else { throw BackupError.damaged("it is from an older version of Rayon") }
        guard let text = String(data: file, encoding: .utf8) else { throw BackupError.damaged("its terminal settings are not text") }
        try terminal.load(text)
        var count = 0
        for key in keys {
            let value = values[key] as? Data
            if value != nil { count += 1 }
            settings.setValue(value, forKey: key)
        }
        return count
    }
}
