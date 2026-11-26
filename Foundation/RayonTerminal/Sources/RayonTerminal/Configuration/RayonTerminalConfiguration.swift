import Foundation
import GhosttyTerminal
import GhosttyTheme

/// The terminal's settings: a `config.ghostty` file in the app's container,
/// applied to the controller every terminal shares. Changing it keeps open
/// terminals, their SSH backends and their scrollback.
@MainActor
public enum RayonTerminalConfiguration {
    static let didApply = Notification.Name("RayonTerminalConfigurationDidApply")

    /// Where the settings live. Settings edits it key by key; anything else
    /// Ghostty understands can be written here by hand.
    public static var fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("config.ghostty")
    }()

    /// The file as last applied.
    public static var contents: String { config.text }

    /// Told the new size when a change sets another font size, so the app's
    /// own zoom starts from it.
    public static var onFontSizeChange: ((Double) -> Void)?

    /// Why the file could not be applied at launch, if it could not.
    private(set) static var loadIssue: String?

    private(set) static var config: GhosttyConfigText = load()

    static var appliedFontSize: Double? { config.value("font-size").flatMap(Double.init) }

    /// The size `TerminalConfiguration.default` gives when the file sets none.
    static var defaultFontSize: Double {
        #if os(iOS)
            10
        #else
            14
        #endif
    }

    /// The app's Copy on Select preference. The app stores it with its own
    /// preferences and sets it here; the file's own value is ignored.
    static private(set) var copyOnSelect = true
    /// The app's Clipboard Sharing preference: programs running on the remote
    /// host may read and write the system clipboard through the terminal
    /// (OSC 52). Like Copy on Select, the app stores it.
    static private(set) var clipboardSharing = true

    /// Keys Rayon sets itself, from the app's preferences or by expanding them.
    static let ownedKeys: Set<String> = ["theme", "copy-on-select", "clipboard-read", "clipboard-write"]

    static let controller: TerminalController = {
        let controller = TerminalController(configuration: .default)
        do { try apply(config, to: controller) } catch { loadIssue = error.localizedDescription }
        return controller
    }()

    /// Validates `text` with Ghostty, applies it to every terminal, then saves
    /// it. Nothing changes when Ghostty rejects it.
    public static func save(_ text: String) throws {
        try commit(GhosttyConfigText(text))
    }

    /// Sets (or, with no values, removes) one key.
    static func set(_ key: String, _ values: [String]) throws {
        var next = config
        next.set(key, values)
        try commit(next)
    }

    static func commit(_ next: GhosttyConfigText) throws {
        guard next != config else { return }
        let oldFontSize = appliedFontSize
        try apply(next, to: controller)
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(next.text.utf8).write(to: fileURL, options: .atomic)
        config = next
        loadIssue = nil
        NotificationCenter.default.post(name: didApply, object: nil)
        if let size = appliedFontSize, size != oldFontSize { onFontSizeChange?(size) }
    }

    /// Applies to every terminal, open ones included, keeping their scrollback.
    static func setCopyOnSelect(_ enabled: Bool) {
        guard copyOnSelect != enabled else { return }
        copyOnSelect = enabled
        try? apply(config, to: controller)
    }

    /// Applies to every terminal, open ones included, keeping their scrollback.
    static func setClipboardSharing(_ enabled: Bool) {
        guard clipboardSharing != enabled else { return }
        clipboardSharing = enabled
        try? apply(config, to: controller)
    }

    /// The light and dark configurations for `config`: its theme's colours
    /// (Ghostty's default pair when it names none), then its own lines, so an
    /// explicit colour wins over the theme, then the app's clipboard policy.
    static func theme(for config: GhosttyConfigText) throws -> TerminalTheme {
        let entries = try config.entries().filter { !ownedKeys.contains($0.key) }
        let clipboard = clipboardSharing ? "allow" : "deny"
        func side(_ name: String?, fallback: TerminalConfiguration) throws -> TerminalConfiguration {
            var base = fallback
            if let name, !name.isEmpty {
                guard let theme = GhosttyThemeCatalog.theme(named: name) else { throw ConfigError("Unknown theme “\(name)”") }
                base = theme.toTerminalConfiguration()
            }
            return entries.reduce(base) { $0.custom($1.key, $1.value) }
                // `clipboard`, not `true`: the runtime advertises a selection
                // clipboard nothing on Apple platforms reads.
                .custom("copy-on-select", copyOnSelect ? "clipboard" : "none")
                .custom("clipboard-read", clipboard)
                .custom("clipboard-write", clipboard)
        }
        let names = themeNames(config.value("theme") ?? "")
        return try TerminalTheme(
            light: side(names.light, fallback: .alabaster),
            dark: side(names.dark, fallback: .afterglow)
        )
    }

    /// `theme = A` names one theme for both appearances; `theme = light:A,dark:B` one for each.
    nonisolated static func themeNames(_ value: String) -> (light: String?, dark: String?) {
        guard value.contains("light:") || value.contains("dark:") else { return (value, value) }
        let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        func side(_ prefix: String) -> String? { parts.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } }
        return (side("light:"), side("dark:"))
    }

    static func apply(_ config: GhosttyConfigText, to target: TerminalController) throws {
        let theme = try theme(for: config)
        // setTheme validates the configuration with Ghostty and keeps the
        // current one when it is rejected.
        if target.theme != theme, !target.setTheme(theme) {
            throw ConfigError(target.lastConfigurationIssue ?? "Ghostty rejected the configuration")
        }
    }

    private static func load() -> GhosttyConfigText {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) { return GhosttyConfigText(text) }
        return GhosttyConfigText()
    }
}
