import Foundation

/// The terminal's settings as the app's iCloud sync sees them: each key set in
/// `config.ghostty` with its values, and a way to take those another device set.
@MainActor
public enum TerminalConfigurationSync {
    public static var overrides: [String: [String]] {
        let entries = (try? RayonTerminalConfiguration.config.entries()) ?? []
        return entries.reduce(into: [:]) { $0[$1.key, default: []].append($1.value) }
    }

    /// Sets (or, for nil, removes) keys and applies them to every terminal.
    /// Changes Ghostty rejects are left out.
    public static func adopt(_ changes: [String: [String]?]) {
        guard !changes.isEmpty else { return }
        var next = RayonTerminalConfiguration.config
        for (key, values) in changes { next.set(key, values ?? []) }
        try? RayonTerminalConfiguration.commit(next)
    }
}
