import SwiftUI

// MARK: - List

extension TerminalSettings {
    /// The shortcuts in effect: after the last `keybind = clear`, the
    /// ones set; else Ghostty's defaults and then the ones set.
    var shortcuts: [String] {
        let own = config["keybind", default: []]
        if let clear = own.lastIndex(of: "clear") { return Array(own[(clear + 1)...]) }
        return (SettingCatalog.shared.setting("keybind")?.defaultValue.values ?? []) + own
    }

    /// Makes `list` the whole set of shortcuts.
    func setShortcuts(_ list: [String]) {
        set("keybind", ["clear"] + list)
    }
}

/// The Keyboard page: every shortcut Rayon's terminal takes, grouped by what
/// it does. Click a shortcut to record new keys; pick its action from the
/// menu beside it; Advanced… edits sequences and Ghostty's own syntax.
struct KeybindingList: View {
    /// Settings search: only the shortcuts with every word of it show.
    var query = ""
    /// The Mac's Keyboard page: a table with +, − and Restore Defaults
    /// beneath it. Otherwise form sections, for a form around them.
    var table = false
    private var settings: TerminalSettings { .shared }
    @State private var editing: Editing?
    /// The row whose recorder is listening; one at a time.
    @State private var recording: Int?
    /// A shortcut being added: its action is chosen, its keys are being
    /// recorded. It is saved once they are, and dropped if recording stops.
    @State private var draft: Keybinding?
    @State private var selection: Set<Int> = []
    @State private var confirmReset = false

    private static let draftID = -1

    private struct Editing: Identifiable {
        let id = UUID()
        /// The shortcut's place in the list; nil for a new one.
        let index: Int?
        var raw: String
    }

    /// A shortcut as shown: `id` is its place in the list.
    private struct Row: Identifiable {
        let id: Int
        let binding: Keybinding
        let raw: String
        /// Why another shortcut with the same keys matters to this one.
        var conflict: String?
    }

    var body: some View {
        let (groups, hidden) = rows()
        if table {
            #if os(macOS)
                presenting(tableView(groups, hidden: hidden))
            #endif
        } else {
            formSections(groups, hidden: hidden)
        }
    }

    /// The dialogs, on one view only: on a group of sections each would get its own.
    private func presenting(_ content: some View) -> some View {
        content
            .confirmationDialog(Text("Restore the default shortcuts?", bundle: .module), isPresented: $confirmReset) {
                Button(.init("Restore", bundle: .module), role: .destructive) { settings.reset("keybind") }
            }
            .sheet(item: $editing) { item in
                KeybindingBuilder(raw: item.raw) { raw in
                    save(Keybinding(raw), at: item.index ?? Self.draftID)
                    editing = nil
                } cancel: {
                    editing = nil
                }
            }
            .onChange(of: recording) { if recording != Self.draftID { draft = nil } }
    }

    // MARK: Rows

    private func rows() -> (groups: [(title: String, rows: [Row])], hidden: Int) {
        let entries = settings.shortcuts
        let parsed = entries.map(Keybinding.init)
        let shown = parsed.indices.filter { KeybindingNames.applies(parsed[$0]) }
        // Ghostty drops a line it cannot read, so only valid ones override.
        let byKeys = Dictionary(grouping: shown.filter { parsed[$0].errors.isEmpty }) { parsed[$0].canonical }
        var rows = shown
            .filter { KeybindingNames.contains(KeybindingNames.searchText(parsed[$0], raw: entries[$0]), every: query) }
            .map { Row(id: $0, binding: parsed[$0], raw: entries[$0], conflict: conflict(of: $0, among: byKeys[parsed[$0].canonical] ?? [], parsed)) }
        if let draft { rows.append(Row(id: Self.draftID, binding: draft, raw: draft.rendered)) }
        let groups = (KeybindingNames.groups.map(\.title) + [KeybindingNames.otherGroup]).compactMap { title -> (title: String, rows: [Row])? in
            let members = rows.filter { KeybindingNames.group(of: $0.binding.action) == title }
            return members.isEmpty ? nil : (title, members)
        }
        return (groups, parsed.count - shown.count)
    }

    /// Ghostty keeps the last of the lines with the same keys.
    private func conflict(of index: Int, among same: [Int], _ parsed: [Keybinding]) -> String? {
        guard same.count > 1, same.contains(index) else { return nil }
        let names = { (indices: [Int]) in
            indices.map { "“\(KeybindingNames.summary(parsed[$0]))”" }.formatted(.list(type: .and))
        }
        let later = same.filter { $0 > index }
        if !later.isEmpty {
            return String(localized: "\(names(later)) uses the same keys and is set later, so it wins.", bundle: .module)
        }
        return String(localized: "Uses the same keys as \(names(same.filter { $0 < index })); this one is set later, so it wins.", bundle: .module)
    }

    // MARK: Changes

    /// Puts `binding` at `index`, or adds it for the draft or a new one.
    private func save(_ binding: Keybinding, at index: Int) {
        var next = settings.shortcuts
        if next.indices.contains(index) { next[index] = binding.rendered } else { next.append(binding.rendered) }
        settings.setShortcuts(next)
    }

    /// Ghostty has no line for an action without keys, so clearing a
    /// shortcut's keys removes it; Undo brings it back.
    private func remove(_ indices: Set<Int>) {
        guard indices.contains(where: { $0 != Self.draftID }) else { return }
        settings.setShortcuts(settings.shortcuts.enumerated().filter { !indices.contains($0.offset) }.map(\.element))
        selection = []
    }

    private func advanced(_ row: Row) {
        editing = Editing(index: row.id == Self.draftID ? nil : row.id, raw: row.raw)
    }

    /// Gives `row` (nil: a new shortcut) another action. One that needs text
    /// or a sequence opens the advanced editor; a number or a choice gets a
    /// default to change there.
    private func choose(_ action: String, argument: String?, for row: Row?) {
        var next = row?.binding ?? Keybinding()
        next.action = action
        next.argument = argument ?? Self.defaultArgument(action)
        let definition = KeybindingCatalog.shared.actionsByName[action]
        let needsText = next.argument == nil && ["text", "free"].contains(definition?.type) && definition?.allowEmpty != true
        if let row, row.id != Self.draftID {
            if needsText { editing = Editing(index: row.id, raw: next.rendered) } else { save(next, at: row.id) }
        } else if needsText || !ShortcutRecorder.canRecord {
            recording = nil
            editing = Editing(index: nil, raw: next.rendered)
        } else {
            draft = next
            recording = Self.draftID
        }
    }

    private static func defaultArgument(_ action: String) -> String? {
        guard let definition = KeybindingCatalog.shared.actionsByName[action] else { return nil }
        switch definition.type {
        case "enum": return definition.allowEmpty == true ? nil : definition.options?.first
        case "number", "integer", "unsignedInteger": return action == "set_font_size" ? "13" : String(Int(max(definition.min ?? 1, 1)))
        case "resize": return "right,10"
        default: return nil
        }
    }

    // MARK: Cells

    private func isRecording(_ id: Int) -> Binding<Bool> {
        Binding(get: { recording == id }, set: { on in
            if on { recording = id } else if recording == id { recording = nil }
        })
    }

    /// The friendly name of what the shortcut does, as a menu of the others.
    /// A name too long for the Action column (in Spanish, at the window's
    /// narrowest) is cut short to the column's width, with all of it in the
    /// tooltip, rather than running into the Shortcut column.
    private func actionMenu(_ row: Row) -> some View {
        let summary = KeybindingNames.summary(row.binding)
        return IdealWidthUpToProposal {
            Menu {
                actionChoices(for: row)
            } label: {
                Text(summary)
            }
            .menuIndicator(.visible)
        }
        .help(summary + "\n" + row.raw)
    }

    @ViewBuilder private func actionChoices(for row: Row?) -> some View {
        ForEach(KeybindingNames.groups, id: \.title) { group in
            Section(group.title) {
                ForEach(group.actions, id: \.self) { action in
                    Button(KeybindingNames.action(action)) { choose(action, argument: nil, for: row) }
                }
            }
        }
        Section(KeybindingNames.lineEditing) {
            ForEach(KeybindingNames.lineEditingSequences, id: \.title) { sequence in
                Button(sequence.title) { choose(sequence.action, argument: sequence.argument, for: row) }
            }
        }
    }

    /// The keys, as a recorder; a sequence, or iOS without a keyboard,
    /// opens the advanced editor instead. Warnings follow.
    @ViewBuilder private func shortcutCell(_ row: Row) -> some View {
        HStack(spacing: 6) {
            if row.binding.steps.count == 1, ShortcutRecorder.canRecord {
                ShortcutRecorder(steps: row.binding.steps, isRecording: isRecording(row.id)) { step in
                    var next = row.binding
                    next.steps = [step]
                    save(next, at: row.id)
                } clear: {
                    remove([row.id])
                }
            } else {
                Button { advanced(row) } label: { ShortcutCaps(steps: row.binding.steps) }
                    .buttonStyle(.plain)
                    .help(Text("Edit in the advanced editor", bundle: .module))
            }
            if !row.binding.errors.isEmpty {
                let errors = row.binding.errors.joined(separator: "\n")
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .help(errors)
                    .accessibilityLabel(errors)
            }
            if let conflict = row.conflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(conflict)
                    .accessibilityLabel(conflict)
            }
        }
    }

    @ViewBuilder private func rowMenu(_ rows: [Row]) -> some View {
        if rows.count == 1, let row = rows.first {
            Button(.init("Advanced…", bundle: .module)) { advanced(row) }
        }
        if rows.contains(where: { $0.id != Self.draftID }) {
            Button(.init("Delete", bundle: .module), role: .destructive) { remove(Set(rows.map(\.id))) }
        }
    }

    private var addMenu: some View {
        Group {
            actionChoices(for: nil)
            Divider()
            Button(.init("Advanced…", bundle: .module)) {
                recording = nil
                editing = Editing(index: nil, raw: Keybinding().rendered)
            }
        }
    }

    private func hiddenNote(_ hidden: Int) -> Text {
        Text("\(hidden) of Ghostty's shortcuts are for windows, tabs and splits, which Rayon manages itself; they are not shown.", bundle: .module)
    }

    // MARK: Layouts

    @ViewBuilder private func formSections(_ groups: [(title: String, rows: [Row])], hidden: Int) -> some View {
        presenting(Section {
            HStack {
                Menu { addMenu } label: { Label(.init("Add Shortcut", bundle: .module), systemImage: "plus") }
                    .fixedSize()
                Spacer()
                Button(.init("Restore Defaults…", bundle: .module)) { confirmReset = true }
                    .disabled(!settings.isSet("keybind"))
            }
            .buttonStyle(.borderless)
        } footer: {
            if hidden > 0 { hiddenNote(hidden) }
        })
        ForEach(groups, id: \.title) { group in
            Section(group.title) {
                ForEach(group.rows) { row in
                    HStack {
                        actionMenu(row)
                        Spacer()
                        shortcutCell(row)
                    }
                    .contextMenu { rowMenu([row]) }
                    .swipeActions {
                        if row.id != Self.draftID {
                            Button(.init("Delete", bundle: .module), role: .destructive) { remove([row.id]) }
                        }
                    }
                }
            }
        }
    }

    #if os(macOS)
        private func tableView(_ groups: [(title: String, rows: [Row])], hidden: Int) -> some View {
            let all = groups.flatMap(\.rows)
            return VStack(spacing: 0) {
                Table(of: Row.self, selection: $selection) {
                    TableColumn(String(localized: "Action", bundle: .module)) { actionMenu($0) }
                    TableColumn(String(localized: "Shortcut", bundle: .module)) { shortcutCell($0) }
                } rows: {
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.rows) { TableRow($0) }
                        }
                    }
                }
                // On the window's material, as the page's form above it.
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: Int.self) { ids in
                    rowMenu(all.filter { ids.contains($0.id) })
                } primaryAction: { ids in
                    if ids.count == 1, let row = all.first(where: { ids.contains($0.id) }) { advanced(row) }
                }
                Divider()
                HStack(spacing: 8) {
                    ControlGroup {
                        Menu { addMenu } label: { Label(.init("Add Shortcut", bundle: .module), systemImage: "plus") }
                            .menuIndicator(.hidden)
                        Button { remove(selection) } label: { Label(.init("Delete Shortcut", bundle: .module), systemImage: "minus") }
                            .disabled(!selection.contains(where: { $0 != Self.draftID }))
                    }
                    .labelStyle(.iconOnly)
                    .fixedSize()
                    if hidden > 0 {
                        hiddenNote(hidden)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            // Before the spacer, and as many lines as the
                            // language needs rather than two cut off.
                            .layoutPriority(1)
                    }
                    Spacer()
                    Button(.init("Restore Defaults…", bundle: .module)) { confirmReset = true }
                        .disabled(!settings.isSet("keybind"))
                        .fixedSize()
                }
                .padding(8)
            }
        }
    #endif
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
            // Without a keyboard to record from, the pickers below set the keys.
            if ShortcutRecorder.canRecord {
                ShortcutRecorder(
                    steps: [step],
                    isRecording: Binding(get: { recordingStep == index }, set: { on in
                        if on { recordingStep = index } else if recordingStep == index { recordingStep = nil }
                    })
                ) { recorded in
                    edit { if $0.steps.indices.contains(index) { $0.steps[index] = recorded } }
                }
            } else {
                KeyCaps(text: KeybindingNames.step(step))
            }
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

/// Its view at its ideal width, or narrower when that is all there is: a
/// menu otherwise takes whatever width it is offered.
private struct IdealWidthUpToProposal: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(.unspecified).width
        return subview.sizeThatFits(ProposedViewSize(width: min(ideal, proposal.width ?? ideal), height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
