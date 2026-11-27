import SwiftUI
#if os(macOS)
    import AppKit
#endif

// MARK: - Names

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

    /// Shell editing keys the defaults send as raw bytes, by what they do.
    private static let knownSequences: [String: String] = [
        "text:\\x01": String(localized: "Move to Start of Line", bundle: .module),
        "text:\\x05": String(localized: "Move to End of Line", bundle: .module),
        "text:\\x15": String(localized: "Delete to Start of Line", bundle: .module),
        "text:\\x0b": String(localized: "Delete to End of Line", bundle: .module),
        "text:\\x17": String(localized: "Delete Previous Word", bundle: .module),
        "esc:b": String(localized: "Move Back a Word", bundle: .module),
        "esc:f": String(localized: "Move Forward a Word", bundle: .module),
        "esc:d": String(localized: "Delete Next Word", bundle: .module),
        "jump_to_prompt:-1": String(localized: "Jump to Previous Prompt", bundle: .module),
        "jump_to_prompt:1": String(localized: "Jump to Next Prompt", bundle: .module),
    ]

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

// MARK: - List

extension TerminalSettings {
    /// The shortcuts in effect: after the file's last `keybind = clear`, its
    /// own; else Ghostty's defaults and then the file's.
    var shortcuts: [String] {
        let own = config.values("keybind")
        if let clear = own.lastIndex(of: "clear") { return Array(own[(clear + 1)...]) }
        return (SettingCatalog.shared.setting("keybind")?.defaultValue.values ?? []) + own
    }

    /// Makes `list` the whole set of shortcuts.
    func setShortcuts(_ list: [String]) {
        set("keybind", ["clear"] + list)
    }
}

/// The Keyboard page: every shortcut Rayon's terminal takes, grouped by what
/// it does, with Add, Edit, Delete and Restore Defaults.
struct KeybindingList: View {
    /// Settings search: only the shortcuts with every word of it show.
    var query = ""
    private var settings: TerminalSettings { .shared }
    @State private var editing: Editing?
    @State private var filter = ""
    @State private var confirmReset = false

    private struct Editing: Identifiable {
        let id = UUID()
        /// The shortcut's place in the list; nil for a new one.
        let index: Int?
        var raw: String
    }

    var body: some View {
        let entries = settings.shortcuts
        let parsed = entries.map(Keybinding.init)
        let counts = Dictionary(parsed.map { ($0.canonical, 1) }, uniquingKeysWith: +)
        let visible = parsed.indices.filter { index in
            let text = KeybindingNames.searchText(parsed[index], raw: entries[index])
            return KeybindingNames.applies(parsed[index])
                && (filter.isEmpty || text.localizedCaseInsensitiveContains(filter))
                && KeybindingNames.contains(text, every: query)
        }
        let hidden = parsed.filter { !KeybindingNames.applies($0) }.count
        Section {
            TextField(String(localized: "Search shortcuts", bundle: .module), text: $filter)
            HStack {
                Button(.init("Add Shortcut", bundle: .module), systemImage: "plus") { editing = Editing(index: nil, raw: Keybinding().rendered) }
                Spacer()
                Button(.init("Restore Defaults…", bundle: .module)) { confirmReset = true }
                    .disabled(!settings.isSet("keybind"))
            }
        } footer: {
            if hidden > 0 {
                Text("\(hidden) of Ghostty's shortcuts are for windows, tabs and splits, which Rayon manages itself; they are not shown.", bundle: .module)
            }
        }
        .confirmationDialog(Text("Restore the default shortcuts?", bundle: .module), isPresented: $confirmReset) {
            Button(.init("Restore", bundle: .module), role: .destructive) { settings.reset("keybind") }
        }
        .sheet(item: $editing) { item in
            KeybindingBuilder(raw: item.raw) { raw in
                var next = entries
                if let index = item.index, next.indices.contains(index) { next[index] = raw } else { next.append(raw) }
                settings.setShortcuts(next)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
        ForEach(KeybindingNames.groups.map(\.title) + [KeybindingNames.otherGroup], id: \.self) { group in
            let members = visible.filter { KeybindingNames.group(of: parsed[$0].action) == group }
            if !members.isEmpty {
                Section(group) {
                    ForEach(members, id: \.self) { index in
                        row(parsed[index], raw: entries[index], duplicate: (counts[parsed[index].canonical] ?? 0) > 1) {
                            editing = Editing(index: index, raw: entries[index])
                        } delete: {
                            settings.setShortcuts(entries.enumerated().filter { $0.offset != index }.map(\.element))
                        }
                    }
                }
            }
        }
    }

    private func row(_ binding: Keybinding, raw: String, duplicate: Bool, edit: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(Array(binding.steps.enumerated()), id: \.offset) { offset, step in
                    if offset > 0 { Text(KeybindingNames.then).font(.caption).foregroundStyle(.secondary) }
                    KeyCaps(text: KeybindingNames.step(step))
                }
            }
            .frame(minWidth: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(KeybindingNames.summary(binding))
                if !binding.errors.isEmpty {
                    Text(binding.errors.joined(separator: "; ")).font(.caption).foregroundStyle(.red)
                }
                if duplicate {
                    Text("Same keys as another shortcut", bundle: .module).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(.init("Edit", bundle: .module), action: edit)
            Button(role: .destructive, action: delete) { Label(.init("Delete Shortcut", bundle: .module), systemImage: "trash") }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(raw)
        .contextMenu {
            Button(.init("Edit…", bundle: .module), action: edit)
            Button(.init("Delete", bundle: .module), role: .destructive, action: delete)
        }
    }
}

// MARK: - Builder

/// One shortcut: its keys (recorded or picked), its action and the action's
/// argument, and when it applies; Ghostty's own syntax underneath.
struct KeybindingBuilder: View {
    @State var raw: String
    let save: (String) -> Void
    let cancel: () -> Void
    @State private var recordingStep: Int?

    init(raw: String, save: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        _raw = State(initialValue: raw)
        self.save = save
        self.cancel = cancel
    }

    private var parsed: Keybinding { Keybinding(raw) }
    private var definition: KeybindingAction? { KeybindingCatalog.shared.actionsByName[parsed.action] }

    private func edit(_ mutation: (inout Keybinding) -> Void) {
        var next = parsed
        mutation(&next)
        raw = next.rendered
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(parsed.steps.enumerated()), id: \.offset) { index, step in
                    Section(parsed.steps.count > 1 ? String(localized: "Keys, step \(index + 1)", bundle: .module) : String(localized: "Keys", bundle: .module)) {
                        stepEditor(index: index, step: step)
                    }
                }
                Section {
                    Button(.init("Add Step", bundle: .module), systemImage: "plus") { edit { $0.steps.append("key_k") } }
                        .disabled(parsed.steps.count >= 4)
                        .help(.init("Make a sequence: press the first keys, release, then the next", bundle: .module))
                }
                Section {
                    Picker(.init("Action", bundle: .module), selection: Binding(get: { parsed.action }, set: { name in edit { $0.action = name; $0.argument = nil } })) {
                        ForEach(KeybindingNames.groups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.actions, id: \.self) { Text(KeybindingNames.action($0)).tag($0) }
                            }
                        }
                    }
                    argumentEditor
                } footer: {
                    if let description = definition?.description { Text(description) }
                }
                Section {
                    Toggle(.init("Also send the keys to the program", bundle: .module), isOn: prefix("unconsumed"))
                    Toggle(.init("Only when the action can run", bundle: .module), isOn: prefix("performable"))
                } header: {
                    Text("When", bundle: .module)
                }
                Section {
                    // A labelled field in a Mac Form trails its text whatever
                    // the alignment; the header names this one.
                    TextField(String(localized: "Ghostty syntax", bundle: .module), text: $raw)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(.body.monospaced())
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Ghostty Syntax", bundle: .module)
                } footer: {
                    if !parsed.errors.isEmpty {
                        Text(parsed.errors.joined(separator: "\n")).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(parsed.steps.isEmpty ? String(localized: "Shortcut", bundle: .module) : KeybindingNames.trigger(parsed))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.init("Cancel", bundle: .module), action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.init("Save", bundle: .module)) { save(raw) }
                        .disabled(!parsed.errors.isEmpty || recordingStep != nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private func prefix(_ name: String) -> Binding<Bool> {
        Binding(get: { parsed.prefixes.contains(name) }, set: { on in
            edit {
                $0.prefixes.removeAll { $0 == name || $0 == "global" || $0 == "all" }
                if on { $0.prefixes.append(name) }
            }
        })
    }

    @ViewBuilder private func stepEditor(index: Int, step: String) -> some View {
        let (mods, key) = Keybinding.splitStep(step)
        HStack {
            KeyCaps(text: recordingStep == index ? String(localized: "Press keys…", bundle: .module) : KeybindingNames.step(step))
            #if os(macOS) || targetEnvironment(macCatalyst)
                Button(recordingStep == index ? String(localized: "Cancel", bundle: .module) : String(localized: "Record", bundle: .module)) {
                    recordingStep = recordingStep == index ? nil : index
                }
                .help(.init("Press the shortcut on the keyboard", bundle: .module))
                .background(KeyRecorder(
                    active: recordingStep == index,
                    record: { recorded in
                        edit { if $0.steps.indices.contains(index) { $0.steps[index] = recorded } }
                        recordingStep = nil
                    },
                    cancel: { recordingStep = nil }
                ))
            #endif
            Spacer()
            if parsed.steps.count > 1 {
                Button(role: .destructive) { edit { $0.steps.remove(at: index) } } label: {
                    Label(.init("Remove Step", bundle: .module), systemImage: "minus.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        HStack {
            ForEach(KeybindingNames.modifiers, id: \.id) { modifier in
                Toggle(modifier.symbol + " " + modifier.name, isOn: Binding(get: { mods.contains(modifier.id) }, set: { on in
                    edit {
                        var (current, key) = Keybinding.splitStep($0.steps[index])
                        current.removeAll { $0 == modifier.id }
                        if on { current.append(modifier.id) }
                        $0.steps[index] = (current.sorted() + [key]).joined(separator: "+")
                    }
                }))
                .toggleStyle(.button)
            }
        }
        Picker(.init("Key", bundle: .module), selection: Binding(get: { key }, set: { name in edit { $0.steps[index] = (mods.sorted() + [name]).joined(separator: "+") } })) {
            ForEach(KeybindingNames.keyGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.keys, id: \.self) { Text(KeybindingNames.key($0)).tag($0) }
                }
            }
            if !KeybindingNames.keyGroups.contains(where: { $0.keys.contains(key) }) {
                Text(KeybindingNames.key(key)).tag(key)
            }
        }
    }

    @ViewBuilder private var argumentEditor: some View {
        if let definition, definition.type != "none" {
            let argument = Binding(get: { parsed.argument ?? "" }, set: { value in edit { $0.argument = value.isEmpty ? nil : value } })
            switch definition.type {
            case "enum":
                Picker(.init("Option", bundle: .module), selection: argument) {
                    if definition.allowEmpty == true { Text("Default", bundle: .module).tag("") }
                    ForEach(definition.options ?? [], id: \.self) { Text(KeybindingNames.option($0)).tag($0) }
                }
            case "number", "integer", "unsignedInteger":
                LabeledContent(definition.name.contains("font") ? String(localized: "Points", bundle: .module) : String(localized: "Amount", bundle: .module)) {
                    HStack {
                        TextField("1", text: argument)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            .frame(width: 80)
                        Stepper(String(localized: "Amount", bundle: .module), onIncrement: { argument.wrappedValue = format((Double(argument.wrappedValue) ?? 0) + 1) },
                                onDecrement: {
                                    let next = (Double(argument.wrappedValue) ?? 0) - 1
                                    argument.wrappedValue = format(definition.type == "unsignedInteger" ? max(0, next) : next)
                                })
                            .labelsHidden()
                    }
                }
            default:
                // In a LabeledContent with its own label hidden: a labelled
                // field in a Mac Form trails its text whatever the alignment.
                LabeledContent(definition.type == "text" ? String(localized: "Text", bundle: .module) : String(localized: "Sequence", bundle: .module)) {
                    TextField(definition.type == "text" ? String(localized: "Text to type (\\n, \\x1b…)", bundle: .module) : String(localized: "Sequence", bundle: .module), text: argument)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(.body.monospaced())
                }
            }
        }
    }

    private func format(_ number: Double) -> String {
        // Beyond this the Int conversion would trap; keep the text as typed.
        guard number.isFinite, abs(number) <= 9e15 else { return String(number) }
        return number.rounded() == number ? String(Int(number)) : String(number)
    }
}


#if os(macOS)
    /// Captures the next key press, with its modifiers, while `active`.
    private struct KeyRecorder: NSViewRepresentable {
        let active: Bool
        let record: (String) -> Void
        /// Only the Catalyst recorder grabs first responder, so only it can
        /// lose it; here the monitor simply never uses this.
        let cancel: () -> Void

        final class Coordinator {
            var monitor: Any?
            var record: ((String) -> Void)?
            deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }
        func makeNSView(context _: Context) -> NSView { NSView() }

        func updateNSView(_: NSView, context: Context) {
            let coordinator = context.coordinator
            coordinator.record = record
            if active, coordinator.monitor == nil {
                coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator] event in
                    guard let coordinator, let step = Self.step(for: event) else { return event }
                    coordinator.record?(step)
                    if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
                    coordinator.monitor = nil
                    return nil
                }
            } else if !active, let monitor = coordinator.monitor {
                NSEvent.removeMonitor(monitor)
                coordinator.monitor = nil
            }
        }

        private static let specialKeys: [UInt16: String] = [
            36: "enter", 48: "tab", 49: "space", 51: "backspace", 53: "escape", 117: "delete",
            115: "home", 119: "end", 116: "page_up", 121: "page_down",
            123: "arrow_left", 124: "arrow_right", 125: "arrow_down", 126: "arrow_up",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
            101: "f9", 109: "f10", 103: "f11", 111: "f12",
        ]

        private static func step(for event: NSEvent) -> String? {
            let flags = event.modifierFlags
            var mods: [String] = []
            if flags.contains(.control) { mods.append("ctrl") }
            if flags.contains(.option) { mods.append("alt") }
            if flags.contains(.shift) { mods.append("shift") }
            if flags.contains(.command) { mods.append("super") }
            let key: String
            if let special = specialKeys[event.keyCode] {
                key = special
            } else if let character = event.characters(byApplyingModifiers: [])?.lowercased(), character.unicodeScalars.count == 1 {
                key = character
            } else {
                return nil
            }
            return (mods.sorted() + [key]).joined(separator: "+")
        }
    }
#elseif targetEnvironment(macCatalyst)
    import UIKit

    /// Captures the next key press, with its modifiers, while `active`.
    private struct KeyRecorder: UIViewRepresentable {
        let active: Bool
        let record: (String) -> Void
        let cancel: () -> Void

        final class Catcher: UIView {
            var record: ((String) -> Void)?
            var cancelled: (() -> Void)?
            /// Mirrors `active` so a queued focus grab dies once recording ended.
            var armed = false
            override var canBecomeFirstResponder: Bool { true }

            override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                for press in presses {
                    if let key = press.key, let step = KeyRecorder.step(for: key) {
                        record?(step)
                        return
                    }
                }
                // A modifier on its own: keep waiting for the key.
            }

            override func resignFirstResponder() -> Bool {
                let resigned = super.resignFirstResponder()
                // A tap into another field ends the recording like Cancel
                // instead of the next body pass grabbing the focus back.
                if resigned { DispatchQueue.main.async { self.cancelled?() } }
                return resigned
            }
        }

        func makeUIView(context _: Context) -> Catcher { Catcher() }

        func updateUIView(_ view: Catcher, context _: Context) {
            view.record = record
            view.cancelled = cancel
            view.armed = active
            if active, !view.isFirstResponder {
                DispatchQueue.main.async { if view.armed { view.becomeFirstResponder() } }
            } else if !active, view.isFirstResponder {
                _ = view.resignFirstResponder()
            }
        }

        private static let specialKeys: [UIKeyboardHIDUsage: String] = [
            .keyboardReturnOrEnter: "enter", .keyboardTab: "tab", .keyboardSpacebar: "space",
            .keyboardDeleteOrBackspace: "backspace", .keyboardEscape: "escape", .keyboardDeleteForward: "delete",
            .keyboardHome: "home", .keyboardEnd: "end", .keyboardPageUp: "page_up", .keyboardPageDown: "page_down",
            .keyboardLeftArrow: "arrow_left", .keyboardRightArrow: "arrow_right",
            .keyboardDownArrow: "arrow_down", .keyboardUpArrow: "arrow_up",
            .keyboardF1: "f1", .keyboardF2: "f2", .keyboardF3: "f3", .keyboardF4: "f4", .keyboardF5: "f5",
            .keyboardF6: "f6", .keyboardF7: "f7", .keyboardF8: "f8", .keyboardF9: "f9", .keyboardF10: "f10",
            .keyboardF11: "f11", .keyboardF12: "f12",
        ]

        /// The unshifted character of the keys whose shifted one differs.
        private static let unshifted: [UIKeyboardHIDUsage: String] = [
            .keyboard1: "1", .keyboard2: "2", .keyboard3: "3", .keyboard4: "4", .keyboard5: "5",
            .keyboard6: "6", .keyboard7: "7", .keyboard8: "8", .keyboard9: "9", .keyboard0: "0",
            .keyboardHyphen: "-", .keyboardEqualSign: "=", .keyboardOpenBracket: "[", .keyboardCloseBracket: "]",
            .keyboardBackslash: "\\", .keyboardSemicolon: ";", .keyboardQuote: "'", .keyboardGraveAccentAndTilde: "`",
            .keyboardComma: ",", .keyboardPeriod: ".", .keyboardSlash: "/",
        ]

        fileprivate static func step(for key: UIKey) -> String? {
            let flags = key.modifierFlags
            var mods: [String] = []
            if flags.contains(.control) { mods.append("ctrl") }
            if flags.contains(.alternate) { mods.append("alt") }
            if flags.contains(.shift) { mods.append("shift") }
            if flags.contains(.command) { mods.append("super") }
            let name: String
            if let special = specialKeys[key.keyCode] {
                name = special
            } else if flags.contains(.shift) || flags.contains(.alternate), let plain = unshifted[key.keyCode] {
                name = plain
            } else {
                let character = key.charactersIgnoringModifiers.lowercased()
                guard character.unicodeScalars.count == 1 else { return nil }
                name = character
            }
            return (mods.sorted() + [name]).joined(separator: "+")
        }
    }
#endif
