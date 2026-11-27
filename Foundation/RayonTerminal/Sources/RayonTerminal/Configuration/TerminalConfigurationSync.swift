import Foundation

/// The terminal's settings as the app's iCloud sync sees them: the keys set
/// that travel, with their values, and a way to take those another device
/// set. What fits one screen (font size, padding) stays on the device.
@MainActor
public enum TerminalConfigurationSync {
    /// Posted, by the `TerminalSettings` concerned, after its settings changed.
    public static let didChange = TerminalSettings.didChange

    /// Keys that suit one device's screen rather than the person.
    public nonisolated static let deviceBoundKeys: Set<String> = ["font-size", "window-padding-x", "window-padding-y"]

    public nonisolated static func syncs(_ key: String) -> Bool {
        SettingCatalog.shared.setting(key) != nil && !deviceBoundKeys.contains(key)
    }

    /// The keys that travel, as applied here.
    public static func entries(of settings: TerminalSettings = .shared) -> [String: [String]] {
        entries(of: settings.applied)
    }

    nonisolated static func entries(of config: [String: [String]]) -> [String: [String]] {
        config.filter { syncs($0.key) }
    }

    /// What makes the keys that travel equal `remote`: each key's new values,
    /// or nil to remove it. Device-bound keys are left alone.
    nonisolated static func changes(from local: [String: [String]], to remote: [String: [String]]) -> [String: [String]?] {
        var result: [String: [String]?] = [:]
        for (key, values) in remote where syncs(key) && local[key] != values {
            result[key] = .some(values)
        }
        for key in local.keys where remote[key] == nil {
            result[key] = .some(nil)
        }
        return result
    }

    /// Makes the keys that travel what another device has, and applies them.
    public static func adopt(_ remote: [String: [String]], into settings: TerminalSettings = .shared) {
        let changes = changes(from: entries(of: settings), to: remote)
        guard !changes.isEmpty else { return }
        settings.adopt(changes)
    }

    /// When the settings last changed, for deciding which side is newer.
    public static func lastWritten(_ settings: TerminalSettings = .shared) -> Date? {
        settings.modified
    }
}
