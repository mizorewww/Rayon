import Foundation
import GhosttyTerminal
import GhosttyTheme

/// The configuration every terminal shares: Rayon's base, the theme's
/// colors, the settings that apply inside Rayon, then the app's clipboard
/// policy. Changing it keeps open terminals, their SSH backends and their
/// scrollback.
@MainActor
enum RayonTerminalConfiguration {
    static let didApply = Notification.Name("RayonTerminalConfigurationDidApply")

    /// The font size the applied settings set, if they set one; terminals
    /// read it when told `didApply`.
    private(set) static var appliedFontSize: Double?

    /// The app's Copy on Select preference. The app stores it with its own
    /// preferences and sets it here; a `copy-on-select` setting is not used.
    private(set) static var copyOnSelect = true
    /// The app's Clipboard Sharing preference: programs running on the remote
    /// host may read and write the system clipboard through the terminal
    /// (OSC 52). Like Copy on Select, the app stores it.
    private(set) static var clipboardSharing = true

    static let controller: TerminalController = {
        let controller = TerminalController(configuration: base)
        do {
            try apply(TerminalSettings.shared.applied, to: controller)
            appliedFontSize = TerminalSettings.shared.applied["font-size"]?.last.flatMap(Double.init)
        } catch {
            TerminalSettings.shared.issue = String(localized: "The terminal settings were not applied: \(error.localizedDescription)", bundle: .module)
        }
        return controller
    }()

    /// `clipboard`, not `true`: the runtime advertises a selection clipboard
    /// that nothing on Apple platforms reads, and `true` may copy only there.
    private static var copyOnSelectValue: String { copyOnSelect ? "clipboard" : "none" }

    /// `allow`/`deny` rather than `ask`: the sharing preference is the user's
    /// answer, so no per-request confirmation is needed.
    private static var clipboardAccessValue: String { clipboardSharing ? "allow" : "deny" }

    /// Applies to every terminal, open ones included, keeping their scrollback.
    static func setCopyOnSelect(_ enabled: Bool) {
        guard copyOnSelect != enabled else { return }
        copyOnSelect = enabled
        try? apply(TerminalSettings.shared.applied)
    }

    /// Applies to every terminal, open ones included, keeping their scrollback.
    static func setClipboardSharing(_ enabled: Bool) {
        guard clipboardSharing != enabled else { return }
        clipboardSharing = enabled
        try? apply(TerminalSettings.shared.applied)
    }

    /// Ghostty's search bindings, which Rayon leaves to its own find bar: with
    /// them bound, Escape ended Ghostty's search instead of reaching the remote
    /// program (vim stayed in insert mode) and left the bar showing a query
    /// whose highlights were gone.
    nonisolated static let unboundTriggers = ["escape", "super+f", "super+shift+f", "super+e", "super+g", "super+shift+g"]

    /// What every terminal starts from, ahead of the user's settings.
    nonisolated static let base: TerminalConfiguration = unboundTriggers.reduce(TerminalConfiguration.default) {
        $0.custom("keybind", "\($1)=unbind")
    }

    /// Values Rayon's terminal starts from where they differ from Ghostty's own
    /// defaults (font size, thickened text, blinking block cursor). Settings
    /// shows these as the defaults, because they are what the terminal uses.
    nonisolated static let runtimeDefaults: [String: [String]] = {
        var result: [String: [String]] = [:]
        for line in TerminalConfiguration.default.rendered.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            result[key, default: []].append(value)
        }
        return result
    }()

    /// The settings Settings shows, but `theme`, which `lines` resolves into colors.
    nonisolated static let supportedKeys: Set<String> = Set(SettingsLayout.categories.flatMap(\.keys)).subtracting(["theme"])

    nonisolated static let supportedActions: Set<String> = [
        "ignore", "unbind", "csi", "esc", "text", "cursor_key", "reset", "copy_to_clipboard", "paste_from_clipboard",
        "paste_from_selection", "copy_url_to_clipboard", "copy_title_to_clipboard", "increase_font_size", "decrease_font_size",
        "reset_font_size", "set_font_size", "clear_screen", "select_all", "scroll_to_top", "scroll_to_bottom",
        "scroll_to_selection", "scroll_to_row", "scroll_page_up", "scroll_page_down", "scroll_page_fractional", "scroll_page_lines",
        "adjust_selection", "jump_to_prompt", "toggle_readonly", "toggle_mouse_reporting", "end_key_sequence",
    ]

    /// Whether a `keybind` value takes effect inside Rayon.
    nonisolated static func applies(keybind value: String) -> Bool {
        if value == "clear" { return true }
        let binding = Keybinding(value)
        return binding.errors.isEmpty && supportedActions.contains(binding.action)
            && !binding.prefixes.contains("global") && !binding.prefixes.contains("all")
    }

    /// The configuration lines for one appearance: the theme's colors, then
    /// the settings that apply inside Rayon, key by key in a fixed order.
    static func lines(for config: [String: [String]], dark: Bool) -> [(key: String, value: String)] {
        var lines: [(key: String, value: String)] = []
        if let theme = TerminalThemes.theme(for: config["theme"]?.last ?? "", dark: dark) {
            lines += ["background", "foreground", "cursor-color", "cursor-text", "selection-background", "selection-foreground"]
                .compactMap { key in theme.color(key).map { (key, $0) } }
            lines += (0 ..< 256).compactMap { index in theme.paletteColor(index).map { ("palette", "\(index)=\($0)") } }
        }
        for (key, values) in config.sorted(by: { $0.key < $1.key }) where supportedKeys.contains(key) {
            for value in values where key != "keybind" || applies(keybind: value) {
                lines.append((key, value))
            }
        }
        lines += [("copy-on-select", copyOnSelectValue), ("clipboard-read", clipboardAccessValue), ("clipboard-write", clipboardAccessValue)]
        return lines
    }

    /// The whole configuration one appearance gets, as Ghostty reads it.
    static func contents(_ config: [String: [String]], dark: Bool) -> String {
        ([base.rendered] + lines(for: config, dark: dark).map { "\($0.key) = \($0.value)" }).joined(separator: "\n")
    }

    /// Applies `config` to `target` (every terminal, by default) once Ghostty
    /// accepts both appearances of it; otherwise throws Ghostty's diagnostics
    /// and changes nothing.
    static func apply(_ config: [String: [String]], to target: TerminalController? = nil) throws {
        let shared = target == nil
        let target = target ?? controller
        let light = contents(config, dark: false)
        let dark = contents(config, dark: true)
        for contents in Set([light, dark]) {
            let validation = TerminalController(configSource: .generated(contents), theme: .init())
            if let issue = validation.lastConfigurationIssue { throw ConfigError(issue) }
        }
        func configuration(_ dark: Bool) -> TerminalConfiguration {
            lines(for: config, dark: dark).reduce(TerminalConfiguration()) { $0.custom($1.key, $1.value) }
        }
        let theme = TerminalTheme(light: configuration(false), dark: configuration(true))
        if target.theme != theme, !target.setTheme(theme) {
            throw ConfigError(target.lastConfigurationIssue ?? String(localized: "Ghostty did not accept the configuration", bundle: .module))
        }
        if shared {
            appliedFontSize = config["font-size"]?.last.flatMap(Double.init)
            NotificationCenter.default.post(name: didApply, object: nil)
        }
    }
}
