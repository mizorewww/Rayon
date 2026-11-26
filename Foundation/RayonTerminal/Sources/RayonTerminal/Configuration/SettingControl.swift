import SwiftUI

/// The control a setting gets, from its catalog entry: one table instead of
/// a view per setting. The few options with an editor of their own (fonts,
/// theme, palette, shortcuts) are named here too.
enum SettingControlKind {
    case toggle
    case slider(ClosedRange<Double>, step: Double)
    case number(min: Double?, max: Double?, step: Double, presets: [Setting.Option])
    case choice([Setting.Option])
    case color(presets: [Setting.Option])
    case text(placeholder: String)
    case list(placeholder: String)
    case flags([Setting.Feature])
    case pair(labels: [String])
    case scrollSpeed
    case duration(allowEmpty: Bool)
    case length
    case bytes
    case theme
    case palette
    case shortcuts
    case fontFamily(placeholder: String)
    case fontStyle
    case fontFeatures
    case fontVariations
    case codepointMap

    init(_ setting: Setting) {
        let widget = setting.widget
        switch setting.key {
        case "font-family": self = .fontFamily(placeholder: "Built-in (JetBrains Mono)"); return
        case "font-family-bold", "font-family-italic", "font-family-bold-italic": self = .fontFamily(placeholder: "Same as the main font"); return
        case "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic": self = .fontStyle; return
        case "font-feature": self = .fontFeatures; return
        case "font-variation", "font-variation-bold", "font-variation-italic", "font-variation-bold-italic": self = .fontVariations; return
        case "font-codepoint-map": self = .codepointMap; return
        case "scrollback-limit", "image-storage-limit": self = .bytes; return
        case "keybind": self = .shortcuts; return
        default: break
        }
        switch widget?.type {
        case "switch": self = .toggle
        case "range": self = .slider((widget?.min ?? 0) ... (widget?.max ?? 1), step: widget?.step ?? 0.01)
        case "number": self = .number(min: widget?.min, max: widget?.max, step: widget?.step ?? 1, presets: [])
        case "custom-number": self = .number(min: widget?.min, max: widget?.max, step: widget?.step ?? 1, presets: widget?.presets ?? [])
        case "dropdown", "pill": self = .choice(widget?.options ?? [])
        case "color": self = .color(presets: [])
        case "custom-color": self = .color(presets: widget?.presets ?? [])
        case "feature-list": self = .flags(widget?.features ?? [])
        case "dual-number": self = .pair(labels: widget?.labels ?? ["First", "Second"])
        case "scroll-multiplier": self = .scrollSpeed
        case "duration": self = .duration(allowEmpty: widget?.allowEmpty == true)
        case "number-units": self = .length
        case "theme": self = .theme
        case "palette": self = .palette
        case "repeatable-text": self = .list(placeholder: widget?.placeholder ?? "Value")
        default:
            self = setting.repeatable == true ? .list(placeholder: widget?.placeholder ?? "Value") : .text(placeholder: widget?.placeholder ?? "Not set")
        }
    }

    /// Editors that take the row's whole width, under its title.
    var isWide: Bool {
        switch self {
        case .list, .flags, .theme, .palette, .shortcuts, .fontFeatures, .fontVariations, .codepointMap: true
        default: false
        }
    }
}

/// One setting in a Form: its title and summary, its control, and Reset and
/// the documentation beside it.
struct SettingRow: View {
    let setting: Setting
    var query = ""
    private var settings: TerminalSettings { .shared }
    @State private var showsHelp = false

    private var kind: SettingControlKind { SettingControlKind(setting) }

    var body: some View {
        if case .shortcuts = kind {
            // The list itself is the Keyboard page; a search result points there.
            LabeledContent {
                Text("\(settings.shortcuts.filter { KeybindingNames.applies(Keybinding($0)) }.count) shortcuts")
                    .foregroundStyle(.secondary)
            } label: {
                label
            }
        } else if kind.isWide {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer()
                    accessories
                }
                SettingControl(setting: setting, kind: kind)
            }
        } else if case .toggle = kind {
            Toggle(isOn: Binding(get: { settings.value(setting.key) == "true" }, set: { settings.set(setting.key, String($0)) })) {
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer()
                    accessories
                }
            }
        } else {
            LabeledContent {
                HStack(spacing: 6) {
                    SettingControl(setting: setting, kind: kind)
                    accessories
                }
            } label: {
                label
            }
        }
    }

    private var title: AttributedString {
        var text = AttributedString(SettingsLayout.title(setting))
        for token in query.split(whereSeparator: \.isWhitespace) {
            if let range = text.range(of: String(token), options: .caseInsensitive) {
                text[range].foregroundColor = .accentColor
                text[range].font = .body.bold()
            }
        }
        return text
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                if setting.deprecated != nil {
                    Text("Deprecated").font(.caption).foregroundStyle(.orange)
                }
            }
            let summary = SettingsLayout.summary(setting)
            if !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .help("Ghostty setting: \(setting.key)")
    }

    @ViewBuilder private var accessories: some View {
        if settings.isSet(setting.key) {
            Button { settings.reset(setting.key) } label: {
                Label("Reset to Default", systemImage: "arrow.counterclockwise")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Reset \(SettingsLayout.title(setting)) to its default")
        }
        Button { showsHelp = true } label: {
            Label("About \(setting.name)", systemImage: "info.circle")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("About \(setting.name)")
        .popover(isPresented: $showsHelp) { SettingHelp(setting: setting) }
    }
}

/// A setting's documentation, as Ghostty writes it.
private struct SettingHelp: View {
    let setting: Setting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(setting.name).font(.headline)
                Text(setting.key).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(LocalizedStringKey(setting.description))
                if let note = setting.note {
                    Text(note.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let platform = setting.platform {
                    Text("Platforms: \(platform.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }
                if let since = setting.since {
                    Text("Since Ghostty \(since)").font(.caption).foregroundStyle(.secondary)
                }
                Link("Ghostty documentation", destination: Setting.documentationURL(setting.key))
            }
            .padding()
            .frame(maxWidth: 420, alignment: .leading)
        }
        .frame(minWidth: 300, idealWidth: 420, maxHeight: 480)
    }
}

/// The control for a kind of setting.
struct SettingControl: View {
    let setting: Setting
    let kind: SettingControlKind
    private var settings: TerminalSettings { .shared }
    @Environment(\.colorScheme) private var scheme

    private var key: String { setting.key }
    private var value: String { settings.value(key) }
    private func set(_ value: String) { settings.set(key, value) }

    var body: some View {
        switch kind {
        case .toggle, .shortcuts:
            EmptyView()
        case let .slider(range, step):
            HStack {
                Slider(value: Binding(get: { Double(value) ?? range.lowerBound }, set: { set($0.configText) }), in: range, step: step)
                    .frame(minWidth: 120, maxWidth: 220)
                Text(value).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 36, alignment: .trailing)
            }
        case let .number(min, max, step, presets):
            HStack(spacing: 6) {
                if !presets.isEmpty {
                    Menu("Presets") {
                        ForEach(presets) { preset in Button(preset.name) { set(preset.value) } }
                    }
                    .fixedSize()
                }
                CommitField(setting.widget?.placeholder ?? "Default", text: value, width: 90) { set($0) }
                Stepper(setting.name, onIncrement: { nudge(+1) }, onDecrement: { nudge(-1) })
                    .labelsHidden()
            }
            .help(rangeHelp(min, max))
        case let .choice(options):
            choice(options)
        case let .color(presets):
            ColorControl(
                effective: settings.effectiveColor(key, dark: scheme == .dark),
                value: settings.isSet(key) ? value : nil,
                presets: presets,
                title: setting.name
            ) { set($0) }
        case let .text(placeholder):
            CommitField(placeholder, text: value, width: 200) { set($0) }
        case let .list(placeholder):
            ListEditor(key: key, placeholder: placeholder)
        case let .flags(features):
            FlagsEditor(value: value, features: features) { set($0) }
        case let .pair(labels):
            PairEditor(value: value, labels: labels, scroll: false, fallback: []) { set($0) }
        case .scrollSpeed:
            PairEditor(value: value, labels: ["Trackpad", "Wheel"], scroll: true,
                       fallback: PairValue.parse(setting.defaultValue.values.first ?? "", scroll: true).values) { set($0) }
        case let .duration(allowEmpty):
            DurationEditor(value: value, allowEmpty: allowEmpty) { set($0) }
        case .length:
            LengthEditor(value: value) { set($0) }
        case .bytes:
            BytesEditor(value: value) { set($0) }
        case .theme:
            ThemeEditor()
        case .palette:
            PaletteEditor()
        case let .fontFamily(placeholder):
            FontFamilyEditor(key: key, placeholder: placeholder)
        case .fontStyle:
            FontStylePicker(key: key)
        case .fontFeatures:
            FontFeatureEditor()
        case .fontVariations:
            FontVariationEditor(key: key)
        case .codepointMap:
            CodepointMapEditor()
        }
    }

    private func nudge(_ sign: Double) {
        guard case let .number(min, max, step, _) = kind else { return }
        let next = (Double(value) ?? 0) + sign * step
        set(Swift.min(max ?? .greatestFiniteMagnitude, Swift.max(min ?? -.greatestFiniteMagnitude, next)).configText)
    }

    private func rangeHelp(_ min: Double?, _ max: Double?) -> String {
        switch (min, max) {
        case let (min?, max?): "From \(min.configText) to \(max.configText)"
        case let (min?, nil): "At least \(min.configText)"
        case let (nil, max?): "At most \(max.configText)"
        default: setting.name
        }
    }

    @ViewBuilder private func choice(_ options: [Setting.Option]) -> some View {
        let names = options.map { SettingsLayout.optionName(key, value: $0.value, fallback: $0.name) }
        let picker = Picker(setting.name, selection: Binding(get: { value }, set: { set($0) })) {
            ForEach(Array(zip(options, names)), id: \.0.value) { option, name in
                Text(name).tag(option.value)
            }
            if !options.contains(where: { $0.value == value }) {
                Text(value.isEmpty ? "Default" : value).tag(value)
            }
        }
        .labelsHidden()
        if options.count <= 3, names.allSatisfy({ $0.count <= 10 }), options.contains(where: { $0.value == value }) {
            picker.pickerStyle(.segmented).fixedSize()
        } else {
            picker.pickerStyle(.menu).fixedSize()
        }
    }
}

// MARK: - Compound values

/// A repeatable setting: one field per value, in order.
private struct ListEditor: View {
    let key: String
    let placeholder: String
    private var settings: TerminalSettings { .shared }

    var body: some View {
        let values = settings.values(key)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack {
                    CommitField(placeholder, text: value, monospaced: true) { text in
                        var next = values
                        next[index] = text
                        settings.set(key, next.filter { !$0.isEmpty })
                    }
                    .multilineTextAlignment(.leading)
                    Button { var next = values; next.swapAt(index, index - 1); settings.set(key, next) } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button(role: .destructive) { var next = values; next.remove(at: index); settings.set(key, next) } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            AddValueField(placeholder: placeholder) { settings.set(key, values + [$0]) }
        }
    }
}

/// A field that adds what is typed into it.
struct AddValueField: View {
    let placeholder: String
    let add: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            // Inside a Form the title would be the field's label, beside
            // an empty field; it is the placeholder instead.
            TextField(placeholder, text: $text, prompt: Text(placeholder))
                .labelsHidden()
                .font(.body.monospaced())
                .onSubmit(commit)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
            Button("Add", systemImage: "plus", action: commit)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        add(value)
        text = ""
    }
}

/// A set of switches written as `a,no-b`: only those that differ from their default.
private struct FlagsEditor: View {
    let value: String
    let features: [Setting.Feature]
    let set: (String) -> Void

    private func isOn(_ feature: Setting.Feature) -> Bool {
        if value == "true" || value == "false" { return value == "true" }
        var result = feature.defaultValue
        for token in value.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if token == feature.id { result = true }
            if token == "no-" + feature.id { result = false }
        }
        return result
    }

    var body: some View {
        HStack {
            ForEach(features) { feature in
                Toggle(feature.label, isOn: Binding(get: { isOn(feature) }, set: { on in
                    var state = Dictionary(uniqueKeysWithValues: features.map { ($0.id, isOn($0)) })
                    state[feature.id] = on
                    set(features.filter { state[$0.id] != $0.defaultValue }
                        .map { state[$0.id] == true ? $0.id : "no-" + $0.id }.joined(separator: ","))
                }))
                .toggleStyle(.button)
                .help(feature.description ?? feature.label)
            }
        }
    }
}

/// Two numbers that may be linked into one (paddings), or the two scroll speeds.
private struct PairEditor: View {
    let value: String
    let labels: [String]
    let scroll: Bool
    let fallback: [String]
    let set: (String) -> Void

    var body: some View {
        let parsed = PairValue.parse(value, scroll: scroll, fallback: fallback.count == 2 ? fallback : ["1", "3"])
        let parts = parsed.values
        HStack(spacing: 6) {
            Text(labels[0]).font(.caption).foregroundStyle(.secondary)
            CommitField(labels[0], text: parts[0], width: 50) {
                set(PairValue.render($0, parsed.linked ? $0 : parts[1], linked: parsed.linked, scroll: scroll))
            }
            if !scroll {
                Toggle(isOn: Binding(get: { parsed.linked }, set: { linked in
                    set(PairValue.render(parts[0], parts[1], linked: linked, scroll: false))
                })) {
                    Label(parsed.linked ? "Linked" : "Separate", systemImage: parsed.linked ? "link" : "link.badge.plus")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help(parsed.linked ? "One value for both; turn off to set them separately" : "Use one value for both")
            }
            Text(labels[1]).font(.caption).foregroundStyle(.secondary)
            CommitField(labels[1], text: parts[1], width: 50) {
                set(PairValue.render(parsed.linked ? $0 : parts[0], $0, linked: parsed.linked, scroll: scroll))
            }
            .disabled(parsed.linked)
        }
    }
}

private struct DurationEditor: View {
    let value: String
    let allowEmpty: Bool
    let set: (String) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            CommitField("e.g. 1h30m", text: value, width: 120, monospaced: true) { set($0) }
            switch Result(catching: { try DurationValue.parse(value, allowEmpty: allowEmpty) }) {
            case let .success(segments):
                if !segments.isEmpty { Text(DurationValue.describe(segments)).font(.caption).foregroundStyle(.secondary) }
            case let .failure(error):
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

/// Points, or a percentage of the font's own value.
private struct LengthEditor: View {
    let value: String
    let set: (String) -> Void

    var body: some View {
        let parsed = LengthValue.parse(value)
        HStack(spacing: 6) {
            CommitField("Default", text: parsed.number, width: 70) { set(LengthValue.render($0, percent: parsed.percent)) }
            Picker("Unit", selection: Binding(get: { parsed.percent }, set: { set(LengthValue.render(parsed.number, percent: $0)) })) {
                Text("pt").tag(false)
                Text("%").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }
}

/// A byte count, edited in megabytes.
private struct BytesEditor: View {
    let value: String
    let set: (String) -> Void
    /// Far below Int.max, so the conversion cannot trap.
    private static let maxMegabytes: Double = 1e12

    private var megabytes: Double { (Double(value) ?? 0) / 1_000_000 }

    private func set(megabytes: Double) {
        set(String(Int(min(max(0, megabytes), Self.maxMegabytes) * 1_000_000)))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("MB", value: Binding(get: { megabytes }, set: { set(megabytes: $0) }), format: .number.precision(.fractionLength(0 ... 1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Stepper("Megabytes", onIncrement: { set(megabytes: megabytes + 1) }, onDecrement: { set(megabytes: megabytes - 1) })
                .labelsHidden()
            Text("MB").foregroundStyle(.secondary)
        }
    }
}
