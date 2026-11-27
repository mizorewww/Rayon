import SwiftUI

/// How keys, shortcuts and actions read in the interface: ⇧⌘K and "Clear Screen"
/// rather than `super+shift+k=clear_screen`.
enum KeybindingNames {
    /// Modifiers in the order macOS menus draw them.
    static let modifiers: [(id: String, symbol: String, name: String)] = [
        ("ctrl", "⌃", String(localized: "Control", bundle: .module)),
        ("alt", "⌥", String(localized: "Option", bundle: .module)),
        ("shift", "⇧", String(localized: "Shift", bundle: .module)),
        ("super", "⌘", String(localized: "Command", bundle: .module)),
    ]

    private static let symbols: [String: String] = [
        "arrow_up": "↑", "arrow_down": "↓", "arrow_left": "←", "arrow_right": "→",
        "enter": "↩", "tab": "⇥", "space": String(localized: "Space", bundle: .module), "backspace": "⌫", "delete": "⌦", "escape": "⎋",
        "page_up": String(localized: "Page Up", bundle: .module),
        "page_down": String(localized: "Page Down", bundle: .module),
        "home": String(localized: "Home", bundle: .module),
        "end": String(localized: "End", bundle: .module),
        "insert": String(localized: "Insert", bundle: .module),
        "equal": "=", "minus": "-", "plus": "+", "comma": ",", "period": ".", "slash": "/", "backslash": "\\",
        "semicolon": ";", "quote": "'", "backquote": "`", "bracket_left": "[", "bracket_right": "]",
    ]

    private static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    static func key(_ raw: String) -> String {
        var name = raw
        if name.hasPrefix("physical:") { name.removeFirst("physical:".count) }
        if let symbol = symbols[name] { return symbol }
        if let digit = numberWords.firstIndex(of: name) { return "\(digit)" }
        if name.hasPrefix("key_"), name.count == 5 { return name.dropFirst(4).uppercased() }
        if name.hasPrefix("digit_") { return String(name.dropFirst(6)) }
        if name.hasPrefix("f"), Int(name.dropFirst()) != nil { return name.uppercased() }
        if name.hasPrefix("numpad_") { return String(localized: "Keypad \(key(String(name.dropFirst(7))))", bundle: .module) }
        if name.unicodeScalars.count == 1 { return name.uppercased() }
        return name.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    static func step(_ step: String) -> String {
        let (mods, key) = Keybinding.splitStep(step)
        return modifiers.filter { mods.contains($0.id) }.map(\.symbol).joined() + self.key(key)
    }

    static func trigger(_ binding: Keybinding) -> String {
        binding.steps.map(step).joined(separator: " \(then) ")
    }

    /// Between the steps of a key sequence.
    static let then = String(localized: "then", bundle: .module)

    /// The group of actions Rayon does not group.
    static let otherGroup = String(localized: "Other", bundle: .module)

    // MARK: Actions

    static let groups: [(title: String, actions: [String])] = [
        (String(localized: "Clipboard", bundle: .module), ["copy_to_clipboard", "paste_from_clipboard", "paste_from_selection", "copy_url_to_clipboard", "copy_title_to_clipboard"]),
        (String(localized: "Text Size", bundle: .module), ["increase_font_size", "decrease_font_size", "reset_font_size", "set_font_size"]),
        (String(localized: "Scrolling", bundle: .module), ["scroll_page_up", "scroll_page_down", "scroll_to_top", "scroll_to_bottom", "scroll_to_selection",
                       "scroll_to_row", "scroll_page_fractional", "scroll_page_lines", "jump_to_prompt"]),
        (String(localized: "Selection", bundle: .module), ["select_all", "adjust_selection"]),
        (String(localized: "Send to Terminal", bundle: .module), ["text", "esc", "csi", "cursor_key"]),
        (String(localized: "Terminal", bundle: .module), ["clear_screen", "reset", "toggle_readonly", "toggle_mouse_reporting"]),
        (String(localized: "Key Handling", bundle: .module), ["ignore", "unbind", "end_key_sequence"]),
    ]

    private static let titles: [String: String] = [
        "copy_to_clipboard": String(localized: "Copy", bundle: .module),
        "paste_from_clipboard": String(localized: "Paste", bundle: .module),
        "paste_from_selection": String(localized: "Paste Selection", bundle: .module),
        "copy_url_to_clipboard": String(localized: "Copy Link", bundle: .module),
        "copy_title_to_clipboard": String(localized: "Copy Title", bundle: .module),
        "increase_font_size": String(localized: "Make Text Bigger", bundle: .module),
        "decrease_font_size": String(localized: "Make Text Smaller", bundle: .module),
        "reset_font_size": String(localized: "Reset Text Size", bundle: .module),
        "set_font_size": String(localized: "Set Text Size", bundle: .module),
        "scroll_page_up": String(localized: "Scroll Up a Page", bundle: .module),
        "scroll_page_down": String(localized: "Scroll Down a Page", bundle: .module),
        "scroll_to_top": String(localized: "Scroll to Top", bundle: .module),
        "scroll_to_bottom": String(localized: "Scroll to Bottom", bundle: .module),
        "scroll_to_selection": String(localized: "Scroll to Selection", bundle: .module),
        "scroll_to_row": String(localized: "Scroll to Row", bundle: .module),
        "scroll_page_fractional": String(localized: "Scroll by Part of a Page", bundle: .module),
        "scroll_page_lines": String(localized: "Scroll by Lines", bundle: .module),
        "jump_to_prompt": String(localized: "Jump to Prompt", bundle: .module),
        "select_all": String(localized: "Select All", bundle: .module),
        "adjust_selection": String(localized: "Extend Selection", bundle: .module),
        "text": String(localized: "Type Text", bundle: .module),
        "esc": String(localized: "Send Escape Sequence", bundle: .module),
        "csi": String(localized: "Send Control Sequence", bundle: .module),
        "cursor_key": String(localized: "Send Cursor Key", bundle: .module),
        "clear_screen": String(localized: "Clear Screen", bundle: .module),
        "reset": String(localized: "Reset Terminal", bundle: .module),
        "toggle_readonly": String(localized: "Toggle Read-Only", bundle: .module),
        "toggle_mouse_reporting": String(localized: "Toggle Mouse Reporting", bundle: .module),
        "ignore": String(localized: "Do Nothing", bundle: .module),
        "unbind": String(localized: "Remove Default Shortcut", bundle: .module),
        "end_key_sequence": String(localized: "End Key Sequence", bundle: .module),
    ]

    static func action(_ name: String) -> String {
        titles[name] ?? name.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    static func option(_ value: String) -> String {
        [
            "plain": String(localized: "Plain text", bundle: .module),
            "vt": String(localized: "Text with terminal styling", bundle: .module),
            "html": "HTML",
            "mixed": String(localized: "Plain and HTML", bundle: .module),
            "page_up": String(localized: "Page up", bundle: .module),
            "page_down": String(localized: "Page down", bundle: .module),
            "beginning_of_line": String(localized: "Start of line", bundle: .module),
            "end_of_line": String(localized: "End of line", bundle: .module),
        ][value] ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Shell editing keys the defaults send as raw bytes, by what they do;
    /// the action menu offers them in this order.
    static let lineEditingSequences: [(action: String, argument: String, title: String)] = [
        ("text", "\\x01", String(localized: "Move to Start of Line", bundle: .module)),
        ("text", "\\x05", String(localized: "Move to End of Line", bundle: .module)),
        ("esc", "b", String(localized: "Move Back a Word", bundle: .module)),
        ("esc", "f", String(localized: "Move Forward a Word", bundle: .module)),
        ("text", "\\x15", String(localized: "Delete to Start of Line", bundle: .module)),
        ("text", "\\x0b", String(localized: "Delete to End of Line", bundle: .module)),
        ("text", "\\x17", String(localized: "Delete Previous Word", bundle: .module)),
        ("esc", "d", String(localized: "Delete Next Word", bundle: .module)),
    ]

    /// The menu section of `lineEditingSequences`.
    static let lineEditing = String(localized: "Line Editing", bundle: .module)

    private static let knownSequences: [String: String] = Dictionary(
        uniqueKeysWithValues: lineEditingSequences.map { ("\($0.action):\($0.argument)", $0.title) } + [
            ("jump_to_prompt:-1", String(localized: "Jump to Previous Prompt", bundle: .module)),
            ("jump_to_prompt:1", String(localized: "Jump to Next Prompt", bundle: .module)),
        ]
    )

    /// "Make Text Bigger (2 pt)" for a binding with an argument.
    static func summary(_ binding: Keybinding) -> String {
        if let known = knownSequences["\(binding.action):\(binding.argument ?? "")"] { return known }
        let title = action(binding.action)
        guard let argument = binding.argument, !argument.isEmpty else { return title }
        if binding.action.hasSuffix("font_size") { return String(localized: "\(title) (\(argument) pt)", bundle: .module) }
        let definition = KeybindingCatalog.shared.actionsByName[binding.action]
        let shown = definition?.type == "enum" ? option(argument) : argument
        return String(localized: "\(title) (\(shown))", bundle: .module)
    }

    /// Rayon applies a binding only if its action exists here and it is not global.
    static func group(of action: String) -> String {
        groups.first { $0.actions.contains(action) }?.title ?? otherGroup
    }

    /// What a shortcut is found by: its keys, what it does and its line.
    static func searchText(_ binding: Keybinding, raw: String) -> String {
        "\(trigger(binding)) \(summary(binding)) \(raw)"
    }

    /// Whether `text` holds every word of `query`, in any order and case.
    static func contains(_ text: String, every query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    static func applies(_ binding: Keybinding) -> Bool {
        RayonTerminalConfiguration.supportedActions.contains(binding.action)
            && !binding.prefixes.contains("global") && !binding.prefixes.contains("all")
    }

    // MARK: Keys

    static let keyGroups: [(title: String, keys: [String])] = {
        let all = KeybindingCatalog.shared.keys
        return [
            (String(localized: "Letters", bundle: .module), all.filter { $0.hasPrefix("key_") }),
            (String(localized: "Numbers", bundle: .module), all.filter { $0.hasPrefix("digit_") }),
            (String(localized: "Punctuation", bundle: .module), ["backquote", "minus", "equal", "bracket_left", "bracket_right", "backslash", "semicolon", "quote", "comma", "period", "slash"]),
            (String(localized: "Navigation", bundle: .module), ["arrow_up", "arrow_down", "arrow_left", "arrow_right", "home", "end", "page_up", "page_down"]),
            (String(localized: "Editing", bundle: .module), ["enter", "tab", "space", "backspace", "delete", "escape", "insert"]),
            (String(localized: "Function Keys", bundle: .module), all.filter { $0.hasPrefix("f") && Int($0.dropFirst()) != nil }),
            (String(localized: "Keypad", bundle: .module), all.filter { $0.hasPrefix("numpad_") }),
        ]
    }()
}

/// Key caps for a shortcut.
struct KeyCaps: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}
