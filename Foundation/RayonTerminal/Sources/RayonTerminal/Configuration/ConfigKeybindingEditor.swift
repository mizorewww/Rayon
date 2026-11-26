import RayonDesign
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
        ("ctrl", "⌃", "Control"), ("alt", "⌥", "Option"), ("shift", "⇧", "Shift"), ("super", "⌘", "Command"),
    ]

    private static let symbols: [String: String] = [
        "arrow_up": "↑", "arrow_down": "↓", "arrow_left": "←", "arrow_right": "→",
        "enter": "↩", "tab": "⇥", "space": "Space", "backspace": "⌫", "delete": "⌦", "escape": "⎋",
        "page_up": "Page Up", "page_down": "Page Down", "home": "Home", "end": "End", "insert": "Insert",
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
        if name.hasPrefix("numpad_") { return "Keypad " + key(String(name.dropFirst(7))) }
        if name.unicodeScalars.count == 1 { return name.uppercased() }
        return name.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    static func step(_ step: String) -> String {
        let (mods, key) = ConfigKeybinding.splitStep(step)
        return modifiers.filter { mods.contains($0.id) }.map(\.symbol).joined() + self.key(key)
    }

    static func trigger(_ binding: ConfigKeybinding) -> String {
        binding.steps.map(step).joined(separator: " then ")
    }

    // MARK: Actions

    static let groups: [(title: String, actions: [String])] = [
        ("Clipboard", ["copy_to_clipboard", "paste_from_clipboard", "paste_from_selection", "copy_url_to_clipboard", "copy_title_to_clipboard"]),
        ("Text Size", ["increase_font_size", "decrease_font_size", "reset_font_size", "set_font_size"]),
        ("Scrolling", ["scroll_page_up", "scroll_page_down", "scroll_to_top", "scroll_to_bottom", "scroll_to_selection",
                       "scroll_to_row", "scroll_page_fractional", "scroll_page_lines", "jump_to_prompt"]),
        ("Selection", ["select_all", "adjust_selection"]),
        ("Send to Terminal", ["text", "esc", "csi", "cursor_key"]),
        ("Terminal", ["clear_screen", "reset", "toggle_readonly", "toggle_mouse_reporting"]),
        ("Key Handling", ["ignore", "unbind", "end_key_sequence"]),
    ]

    private static let titles: [String: String] = [
        "copy_to_clipboard": "Copy", "paste_from_clipboard": "Paste", "paste_from_selection": "Paste Selection",
        "copy_url_to_clipboard": "Copy Link", "copy_title_to_clipboard": "Copy Title",
        "increase_font_size": "Make Text Bigger", "decrease_font_size": "Make Text Smaller",
        "reset_font_size": "Reset Text Size", "set_font_size": "Set Text Size",
        "scroll_page_up": "Scroll Up a Page", "scroll_page_down": "Scroll Down a Page",
        "scroll_to_top": "Scroll to Top", "scroll_to_bottom": "Scroll to Bottom", "scroll_to_selection": "Scroll to Selection",
        "scroll_to_row": "Scroll to Row", "scroll_page_fractional": "Scroll by Part of a Page", "scroll_page_lines": "Scroll by Lines",
        "jump_to_prompt": "Jump to Prompt", "select_all": "Select All", "adjust_selection": "Extend Selection",
        "text": "Type Text", "esc": "Send Escape Sequence", "csi": "Send Control Sequence", "cursor_key": "Send Cursor Key",
        "clear_screen": "Clear Screen", "reset": "Reset Terminal", "toggle_readonly": "Toggle Read-Only",
        "toggle_mouse_reporting": "Toggle Mouse Reporting",
        "ignore": "Do Nothing", "unbind": "Remove Default Shortcut", "end_key_sequence": "End Key Sequence",
    ]

    static func action(_ name: String) -> String {
        titles[name] ?? name.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    static func option(_ value: String) -> String {
        [
            "plain": "Plain text", "vt": "Text with terminal styling", "html": "HTML", "mixed": "Plain and HTML",
            "page_up": "Page up", "page_down": "Page down", "beginning_of_line": "Start of line", "end_of_line": "End of line",
        ][value] ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Shell editing keys the defaults send as raw bytes, by what they do.
    private static let knownSequences: [String: String] = [
        "text:\\x01": "Move to Start of Line", "text:\\x05": "Move to End of Line",
        "text:\\x15": "Delete to Start of Line", "text:\\x0b": "Delete to End of Line",
        "text:\\x17": "Delete Previous Word", "esc:b": "Move Back a Word", "esc:f": "Move Forward a Word",
        "esc:d": "Delete Next Word", "jump_to_prompt:-1": "Jump to Previous Prompt", "jump_to_prompt:1": "Jump to Next Prompt",
    ]

    /// "Make Text Bigger (2 pt)" for a binding with an argument.
    static func summary(_ binding: ConfigKeybinding) -> String {
        if let known = knownSequences["\(binding.action):\(binding.argument ?? "")"] { return known }
        let title = action(binding.action)
        guard let argument = binding.argument, !argument.isEmpty else { return title }
        if binding.action.hasSuffix("font_size") { return "\(title) (\(argument) pt)" }
        let definition = ConfigKeybindingCatalog.shared.actions.first { $0.name == binding.action }
        return "\(title) (\(definition?.type == "enum" ? option(argument) : argument))"
    }

    /// Rayon applies a binding only if its action exists here and it is not global.
    static func group(of action: String) -> String {
        groups.first { $0.actions.contains(action) }?.title ?? "Other"
    }

    static func applies(_ binding: ConfigKeybinding) -> Bool {
        RayonTerminalConfiguration.supportedActions.contains(binding.action)
            && !binding.prefixes.contains("global") && !binding.prefixes.contains("all")
    }

    // MARK: Keys

    static let keyGroups: [(title: String, keys: [String])] = {
        let all = ConfigKeybindingCatalog.shared.keys
        return [
            ("Letters", all.filter { $0.hasPrefix("key_") }),
            ("Numbers", all.filter { $0.hasPrefix("digit_") }),
            ("Punctuation", ["backquote", "minus", "equal", "bracket_left", "bracket_right", "backslash", "semicolon", "quote", "comma", "period", "slash"]),
            ("Navigation", ["arrow_up", "arrow_down", "arrow_left", "arrow_right", "home", "end", "page_up", "page_down"]),
            ("Editing", ["enter", "tab", "space", "backspace", "delete", "escape", "insert"]),
            ("Function Keys", all.filter { $0.hasPrefix("f") && Int($0.dropFirst()) != nil }),
            ("Keypad", all.filter { $0.hasPrefix("numpad_") }),
        ]
    }()
}

/// Key caps for a shortcut.
struct KeyCaps: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.rxInk)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.rxSurfaceSunken))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.rxHairline))
    }
}

// MARK: - List

struct ConfigKeybindingList: View {
    let model: ConfigEditorModel
    /// Drawn again when the shortcuts change, not when any setting does.
    @ObservedObject private var scope: ConfigEditorModel.Scope
    @State private var editIndex: Int?
    @State private var draft = ConfigKeybinding().rendered
    @State private var editing = false
    @State private var filter = ""
    @State private var confirmReset = false

    init(model: ConfigEditorModel) {
        self.model = model
        scope = model.scope("keybind")
    }

    private var entries: [String] { model.document.values("keybind") }

    /// The shortcuts read once: those to list, how many are not Rayon's to
    /// offer, and the key sequences more than one of them uses.
    private struct Listing {
        var visible: [(index: Int, binding: ConfigKeybinding)] = []
        var hiddenCount = 0
        var repeated: Set<String> = []

        init(entries: [String], filter: String) {
            var seen: [String: Int] = [:]
            for (index, entry) in entries.enumerated() {
                let binding = ConfigKeybinding(entry)
                seen[binding.canonical, default: 0] += 1
                guard KeybindingNames.applies(binding) else { hiddenCount += 1; continue }
                if !filter.isEmpty {
                    let text = "\(KeybindingNames.trigger(binding)) \(KeybindingNames.summary(binding)) \(entry)"
                    guard text.localizedCaseInsensitiveContains(filter) else { continue }
                }
                visible.append((index, binding))
            }
            repeated = Set(seen.filter { $0.value > 1 }.keys)
        }
    }

    /// Parses every shortcut once per (entries, filter) pair: body runs on
    /// each sheet and search state change, the parsed list rarely does.
    private final class ListingCache {
        private var entries: [String] = []
        private var filter = ""
        private var value: Listing?

        func listing(entries: [String], filter: String) -> Listing {
            if let value, self.entries == entries, self.filter == filter { return value }
            let built = Listing(entries: entries, filter: filter)
            self.entries = entries
            self.filter = filter
            value = built
            return built
        }
    }

    @State private var listingCache = ListingCache()

    private var listing: Listing {
        listingCache.listing(entries: entries, filter: filter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            // One row when it fits; on a narrow screen the buttons go under the search.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RX.Space.s2) {
                    RXSearchField("Search shortcuts", text: $filter, width: 220)
                    Spacer()
                    headerButtons
                }
                VStack(alignment: .leading, spacing: RX.Space.s2) {
                    RXSearchField("Search shortcuts", text: $filter, width: nil)
                    HStack(spacing: RX.Space.s2) { headerButtons }
                }
            }
            let listing = listing
            let rows = listing.visible
            let hiddenCount = listing.hiddenCount
            ForEach(KeybindingNames.groups.map(\.title) + ["Other"], id: \.self) { group in
                let members = rows.filter { KeybindingNames.group(of: $0.binding.action) == group }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: RX.Space.s2) {
                        CapsLabel(group)
                            .padding(.leading, RX.Space.s4)
                        RXDividedStack {
                            ForEach(members, id: \.index) { index, binding in
                                row(index: index, binding: binding, duplicate: listing.repeated.contains(binding.canonical))
                            }
                        }
                        .padding(.horizontal, RX.Space.s4)
                        .background(Color.clear.rxCard(padding: 0))
                    }
                }
            }
            if hiddenCount > 0 {
                HelpText("\(hiddenCount) of Ghostty's shortcuts are for windows, tabs and splits, which Rayon manages itself; they are not shown.")
            }
        }
        .confirmationDialog("Restore the default shortcuts?", isPresented: $confirmReset) {
            Button("Restore", role: .destructive) { model.reset("keybind") }
        }
        .sheet(isPresented: $editing) {
            ConfigKeybindingBuilder(raw: $draft) {
                model.edit { document in
                    var values = document.values("keybind")
                    if let editIndex, values.indices.contains(editIndex) { values[editIndex] = draft } else { values.append(draft) }
                    document.set("keybind", values)
                }
                editing = false
            }
        }
    }

    @ViewBuilder private var headerButtons: some View {
        Button("Restore Defaults…") { confirmReset = true }
            .buttonStyle(.rx)
            .disabled(model.document.overrides["keybind"] == nil)
            .fixedSize()
        Button {
            editIndex = nil
            draft = ConfigKeybinding().rendered
            editing = true
        } label: {
            Label("Add Shortcut", systemImage: "plus")
        }
        .buttonStyle(.rxPrimary)
        .fixedSize()
    }

    private func row(index: Int, binding: ConfigKeybinding, duplicate: Bool) -> some View {
        HStack(spacing: RX.Space.s3) {
            HStack(spacing: 4) {
                ForEach(Array(binding.steps.enumerated()), id: \.offset) { offset, step in
                    if offset > 0 { Text("then").font(.rxHelp).foregroundStyle(.rxInkSecondary) }
                    KeyCaps(text: KeybindingNames.step(step))
                }
            }
            .frame(minWidth: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(KeybindingNames.summary(binding))
                    .font(.rxBody)
                    .foregroundStyle(.rxInk)
                if !binding.errors.isEmpty {
                    HelpText(binding.errors.joined(separator: "; "), isError: true)
                }
            }
            Spacer()
            if duplicate {
                RXTag("Same keys as another shortcut", style: .warning)
            }
            Button("Edit") {
                editIndex = index
                draft = entries[index]
                editing = true
            }
            .buttonStyle(.rx(size: .small))
            RXIconButton("Delete Shortcut", systemImage: "trash", kind: .plain, size: .small) {
                model.edit { $0.set("keybind", entries.enumerated().filter { $0.offset != index }.map(\.element)) }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: RX.tableRowHeight)
        .help(entries[index])
    }
}

// MARK: - Builder

struct ConfigKeybindingBuilder: View {
    @Binding var raw: String
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recordingStep: Int?
    @State private var showsSyntax = false

    private var parsed: ConfigKeybinding { ConfigKeybinding(raw) }
    private var definition: ConfigAction? { ConfigKeybindingCatalog.shared.actions.first { $0.name == parsed.action } }

    private func edit(_ mutation: (inout ConfigKeybinding) -> Void) {
        var next = parsed
        mutation(&next)
        raw = next.rendered
    }

    var body: some View {
        SheetScaffold(parsed.steps.isEmpty ? "Shortcut" : KeybindingNames.trigger(parsed)) {
            VStack(alignment: .leading, spacing: RX.Space.s4) {
                ForEach(Array(parsed.steps.enumerated()), id: \.offset) { index, step in
                    RXField(parsed.steps.count > 1 ? "Keys · step \(index + 1)" : "Keys") {
                        stepEditor(index: index, step: step)
                    }
                }
                Button {
                    edit { $0.steps.append("key_k") }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .buttonStyle(.rx(.plain, size: .small))
                .disabled(parsed.steps.count >= 4)
                .help("Make a sequence: press the first keys, release, then the next")

                RXField("Action", help: definition?.description) {
                    Picker("Action", selection: Binding(get: { parsed.action }, set: { name in edit { $0.action = name; $0.argument = nil } })) {
                        ForEach(KeybindingNames.groups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.actions, id: \.self) { name in
                                    Text(KeybindingNames.action(name)).tag(name)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                argumentEditor

                RXField("When") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Also send the keys to the program", isOn: prefix("unconsumed"))
                        Toggle("Only when the action can run", isOn: prefix("performable"))
                    }
                    .rxCheckboxToggle()
                    .font(.rxBody)
                }

                DisclosureGroup("Ghostty syntax", isExpanded: $showsSyntax) {
                    TextField("Binding", text: $raw)
                        .textFieldStyle(.rxMono)
                        .padding(.top, RX.Space.s1)
                }
                .font(.rxHelp)
                if !parsed.errors.isEmpty {
                    HelpText(parsed.errors.joined(separator: "\n"), isError: true)
                }
            }
        } footer: {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.rx)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!parsed.errors.isEmpty || recordingStep != nil)
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(width: 580)
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

    private func stepEditor(index: Int, step: String) -> some View {
        let (mods, key) = ConfigKeybinding.splitStep(step)
        return VStack(alignment: .leading, spacing: RX.Space.s2) {
            HStack(spacing: RX.Space.s2) {
                KeyCaps(text: recordingStep == index ? "Press keys…" : KeybindingNames.step(step))
                #if os(macOS) || targetEnvironment(macCatalyst)
                    Button(recordingStep == index ? "Cancel" : "Record") {
                        recordingStep = recordingStep == index ? nil : index
                    }
                    .buttonStyle(.rx(size: .small))
                    .help("Press the shortcut on the keyboard")
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
                    RXIconButton("Remove Step", systemImage: "minus.circle", kind: .plain, size: .small) {
                        edit { $0.steps.remove(at: index) }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(KeybindingNames.modifiers, id: \.id) { modifier in
                    RXChip("\(modifier.symbol) \(modifier.name)", isOn: mods.contains(modifier.id)) {
                        edit {
                            var (current, key) = ConfigKeybinding.splitStep($0.steps[index])
                            if current.contains(modifier.id) { current.removeAll { $0 == modifier.id } } else { current.append(modifier.id) }
                            $0.steps[index] = (current.sorted() + [key]).joined(separator: "+")
                        }
                    }
                }
                Menu {
                    ForEach(KeybindingNames.keyGroups, id: \.title) { group in
                        Menu(group.title) {
                            ForEach(group.keys, id: \.self) { name in
                                Button(KeybindingNames.key(name)) {
                                    edit { $0.steps[index] = (mods.sorted() + [name]).joined(separator: "+") }
                                }
                            }
                        }
                    }
                } label: {
                    Text("Key: \(KeybindingNames.key(key))")
                }
                .rxButtonMenu()
                .buttonStyle(.rx(size: .small))
                .fixedSize()
            }
        }
    }

    @ViewBuilder private var argumentEditor: some View {
        if let definition, definition.type != "none" {
            let argument = Binding(get: { parsed.argument ?? "" }, set: { value in edit { $0.argument = value.isEmpty ? nil : value } })
            switch definition.type {
            case "enum":
                RXField("Option") {
                    Picker("Option", selection: argument) {
                        if definition.allowEmpty == true { Text("Default").tag("") }
                        ForEach(definition.options ?? [], id: \.self) { Text(KeybindingNames.option($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            case "number", "integer", "unsignedInteger":
                RXField(definition.name.contains("font") ? "Points" : "Amount") {
                    HStack(spacing: RX.Space.s1) {
                        TextField("1", text: argument)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.rx)
                            .frame(width: 80)
                        Stepper("Amount", onIncrement: { argument.wrappedValue = format((Double(argument.wrappedValue) ?? 0) + 1) },
                                onDecrement: {
                                    let next = (Double(argument.wrappedValue) ?? 0) - 1
                                    argument.wrappedValue = format(definition.type == "unsignedInteger" ? max(0, next) : next)
                                })
                                .labelsHidden()
                    }
                }
            default:
                RXField(definition.type == "text" ? "Text to type" : "Sequence",
                        help: definition.type == "text" ? "Escapes such as \\n and \\x1b are allowed." : nil) {
                    TextField(definition.type == "text" ? "Text" : "Sequence", text: argument)
                        .textFieldStyle(.rxMono)
                }
            }
        }
    }

    private func format(_ number: Double) -> String {
        // beyond this the Int conversion would trap; keep the free-form text as typed
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
