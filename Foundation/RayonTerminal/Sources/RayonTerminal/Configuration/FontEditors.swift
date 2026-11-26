import RayonDesign
import SwiftUI

/// The family a per-style setting applies to: its own family, else the main font.
@MainActor
private func family(for key: String, prefix: String) -> String {
    let settings = TerminalSettings.shared
    let own = key.replacingOccurrences(of: prefix, with: "font-family")
    return settings.config.values(own).first ?? settings.config.values("font-family").first ?? ""
}

/// A button showing the chosen family in its own typeface; it opens the
/// list of installed fonts.
struct FontPicker: View {
    @Binding var family: String
    let placeholder: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack {
                Text(family.isEmpty ? placeholder : family)
                    .font(family.isEmpty ? .body : .custom(family, size: 13))
                    .foregroundStyle(family.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help("Choose an installed font")
        .popover(isPresented: $open) {
            FontFamilyList(selection: $family, placeholder: placeholder) { open = false }
        }
    }
}

/// Installed families, each in its own typeface, searchable, monospaced
/// ones only by default: a terminal needs fixed-width glyphs.
private struct FontFamilyList: View {
    @Binding var selection: String
    let placeholder: String
    let done: () -> Void
    @State private var search = ""
    @State private var monospacedOnly: Bool

    init(selection: Binding<String>, placeholder: String, done: @escaping () -> Void) {
        _selection = selection
        self.placeholder = placeholder
        self.done = done
        let current = selection.wrappedValue
        _monospacedOnly = State(initialValue: current.isEmpty || FontLibrary.isMonospaced(current))
    }

    private var families: [FontLibrary.Family] {
        FontLibrary.families.filter { family in
            (!monospacedOnly || family.monospaced) && (search.isEmpty || family.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search fonts", text: $search).textFieldStyle(.roundedBorder)
            Toggle("Monospaced fonts only", isOn: $monospacedOnly)
            ScrollViewReader { proxy in
                List {
                    row(name: "", title: placeholder, font: .body)
                    ForEach(families) { family in
                        row(name: family.name, title: family.name, font: .custom(family.name, size: 14)).id(family.name)
                    }
                }
                .listStyle(.plain)
                .onAppear { if !selection.isEmpty { proxy.scrollTo(selection, anchor: .center) } }
            }
            if families.isEmpty { Text("No installed font matches.").foregroundStyle(.secondary) }
        }
        .padding()
        .frame(minWidth: 320, idealWidth: 340, minHeight: 420, idealHeight: 520)
    }

    private func row(name: String, title: String, font: Font) -> some View {
        Button {
            selection = name
            done()
        } label: {
            HStack {
                Text(title).font(font).lineLimit(1)
                Spacer()
                if selection == name { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `font-family…`: the font, then fallbacks tried in order for characters it lacks.
struct FontFamilyEditor: View {
    let key: String
    let placeholder: String
    private var settings: TerminalSettings { .shared }
    @State private var addingFallback = false

    var body: some View {
        let families = settings.config.values(key)
        VStack(alignment: .trailing, spacing: 6) {
            FontPicker(family: Binding(get: { families.first ?? "" }, set: { name in
                var next = families
                if next.isEmpty { next = [name] } else { next[0] = name }
                settings.set(key, next.filter { !$0.isEmpty })
            }), placeholder: placeholder)
            ForEach(Array(families.enumerated().dropFirst()), id: \.offset) { index, family in
                HStack {
                    Text("Fallback").font(.caption).foregroundStyle(.secondary)
                    FontPicker(family: Binding(get: { family }, set: { name in
                        var next = families
                        next[index] = name
                        settings.set(key, next.filter { !$0.isEmpty })
                    }), placeholder: "Choose…")
                    Button(role: .destructive) {
                        var next = families
                        next.remove(at: index)
                        settings.set(key, next)
                    } label: { Label("Remove Fallback", systemImage: "minus.circle") }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            if !families.isEmpty {
                if addingFallback {
                    HStack {
                        Text("Fallback").font(.caption).foregroundStyle(.secondary)
                        FontPicker(family: Binding(get: { "" }, set: { name in
                            addingFallback = false
                            if !name.isEmpty { settings.set(key, families + [name]) }
                        }), placeholder: "Choose…")
                        Button("Cancel") { addingFallback = false }.buttonStyle(.borderless)
                    }
                } else {
                    Button("Add Fallback", systemImage: "plus") { addingFallback = true }
                        .buttonStyle(.borderless)
                        .help("Used for characters the font does not have")
                }
            }
        }
    }
}

/// `font-style…`: the styles the family actually has.
struct FontStylePicker: View {
    let key: String
    private var settings: TerminalSettings { .shared }

    var body: some View {
        let family = family(for: key, prefix: "font-style")
        let styles = FontLibrary.styles(of: family)
        let value = settings.value(key)
        Picker("Style", selection: Binding(get: { value }, set: { settings.set(key, $0) })) {
            Text("Default").tag("default")
            if key != "font-style" { Text("Disabled (use regular)").tag("false") }
            Divider()
            ForEach(styles, id: \.self) { Text($0).tag($0) }
            if !["default", "false"].contains(value), !styles.contains(value) {
                Text(value).tag(value)
            }
        }
        .labelsHidden()
        .fixedSize()
        .help(family.isEmpty ? "Styles of the built-in font" : "Styles installed for \(family)")
    }
}

/// `font-feature`: the font's OpenType features as switches, grouped as the
/// font groups them. A switch left at the font's default writes nothing.
struct FontFeatureEditor: View {
    private var settings: TerminalSettings { .shared }

    /// `tag`, `+tag`, `tag=1` turn a feature on; `-tag`, `tag=0` turn it off.
    static func parse(_ entry: String) -> (tag: String, on: Bool) {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("-") { return (String(trimmed.dropFirst()), false) }
        if trimmed.hasPrefix("+") { return (String(trimmed.dropFirst()), true) }
        if let eq = trimmed.firstIndex(of: "=") {
            let value = trimmed[trimmed.index(after: eq)...].lowercased()
            return (String(trimmed[..<eq]), !["0", "off", "false"].contains(value))
        }
        return (trimmed, true)
    }

    var body: some View {
        let family = settings.config.values("font-family").first ?? ""
        let entries = settings.config.values("font-feature")
        let features = FontLibrary.features(of: family)
        let known = Set(features.map(\.tag))
        let groups = features.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        VStack(alignment: .leading, spacing: 10) {
            if features.isEmpty { Text("\(family) has no OpenType features to switch.").foregroundStyle(.secondary) }
            ForEach(groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group).font(.caption).foregroundStyle(.secondary)
                    RXFlowLayout {
                        ForEach(features.filter { $0.group == group }) { feature in
                            let on = entries.last { Self.parse($0).tag == feature.tag }.map { Self.parse($0).on } ?? feature.defaultOn
                            Toggle(feature.name, isOn: Binding(get: { on }, set: { now in
                                var next = entries.filter { Self.parse($0).tag != feature.tag }
                                if now != feature.defaultOn { next.append(now ? feature.tag : "-" + feature.tag) }
                                settings.set("font-feature", next)
                            }))
                            .toggleStyle(.button)
                            .help("\(feature.tag)\(feature.defaultOn ? " · on by default" : "")")
                        }
                    }
                }
            }
            let others = entries.filter { !known.contains(Self.parse($0).tag) }
            if !others.isEmpty {
                Text("Other").font(.caption).foregroundStyle(.secondary)
                RXFlowLayout {
                    ForEach(others, id: \.self) { entry in
                        Button(entry, systemImage: "xmark.circle") { settings.set("font-feature", entries.filter { $0 != entry }) }
                            .help("Remove \(entry)")
                    }
                }
            }
            AddValueField(placeholder: "Other feature, e.g. ss07 or -liga") { value in
                settings.set("font-feature", entries.filter { Self.parse($0).tag != Self.parse(value).tag } + [value])
            }
            if family.isEmpty {
                Text("These are the built-in font's features; choose a font under Font to see its own.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// `font-variation…`: a slider per axis of the chosen variable font. An axis
/// left at its default writes nothing.
struct FontVariationEditor: View {
    let key: String
    private var settings: TerminalSettings { .shared }

    var body: some View {
        let family = family(for: key, prefix: "font-variation")
        let axes = FontLibrary.axes(of: family)
        let entries = settings.config.values(key)
        VStack(alignment: .leading, spacing: 6) {
            if family.isEmpty {
                Text("Choose a variable font under Font to adjust its axes.").foregroundStyle(.secondary)
            } else if axes.isEmpty {
                Text("\(family) is not a variable font.").foregroundStyle(.secondary)
            }
            ForEach(axes) { axis in
                let value = entries.reversed().lazy.compactMap { entry -> Double? in
                    let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    return parts.count == 2 && parts[0] == axis.tag ? Double(parts[1]) : nil
                }.first ?? axis.defaultValue
                LabeledContent {
                    HStack {
                        Slider(value: Binding(get: { value }, set: { number in
                            var next = entries.filter { !$0.hasPrefix(axis.tag + "=") }
                            if abs(number - axis.defaultValue) > 0.0001 { next.append("\(axis.tag)=\(number.configText)") }
                            settings.set(key, next)
                        }), in: axis.minimum ... max(axis.maximum, axis.minimum + 0.01), step: axis.maximum - axis.minimum > 10 ? 1 : 0.01)
                        Text(value.configText).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 40, alignment: .trailing)
                    }
                } label: {
                    Text(axis.name).help(axis.tag)
                }
            }
        }
    }
}

/// `font-codepoint-map`: "these characters use this font", one rule per row.
struct CodepointMapEditor: View {
    private var settings: TerminalSettings { .shared }
    @State private var pending: CodepointMapping?

    var body: some View {
        let entries = settings.config.values("font-codepoint-map")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let remove = { settings.set("font-codepoint-map", entries.enumerated().filter { $0.offset != index }.map(\.element)) }
                if let mapping = CodepointMapping(entry) {
                    row(
                        ranges: Binding(get: { mapping.ranges }, set: { ranges in
                            var next = entries
                            next[index] = CodepointMapping(ranges: ranges, family: mapping.family).rendered
                            settings.set("font-codepoint-map", next)
                        }),
                        family: Binding(get: { mapping.family }, set: { family in
                            var next = entries
                            next[index] = CodepointMapping(ranges: mapping.ranges, family: family).rendered
                            settings.set("font-codepoint-map", next)
                        }),
                        remove: remove
                    )
                } else {
                    HStack {
                        Text(entry).font(.body.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        removeButton(remove)
                    }
                }
            }
            if let pending {
                row(
                    ranges: Binding(get: { pending.ranges }, set: { self.pending?.ranges = $0 }),
                    family: Binding(get: { "" }, set: { family in
                        guard !family.isEmpty else { return }
                        settings.set("font-codepoint-map", entries + [CodepointMapping(ranges: pending.ranges, family: family).rendered])
                        self.pending = nil
                    }),
                    remove: { self.pending = nil }
                )
            } else {
                Button("Add Rule", systemImage: "plus") {
                    pending = CodepointMapping(ranges: CodepointRangeSet.presets[0].ranges, family: "")
                }
            }
        }
    }

    private func row(ranges: Binding<String>, family: Binding<String>, remove: @escaping () -> Void) -> some View {
        HStack {
            CodepointRangePicker(ranges: ranges)
            Text("use").foregroundStyle(.secondary)
            FontPicker(family: family, placeholder: "Choose a font…")
            Spacer()
            removeButton(remove)
        }
    }

    private func removeButton(_ remove: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: remove) { Label("Remove Rule", systemImage: "minus.circle") }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
    }
}

/// A named character set, or ranges typed as Ghostty writes them.
private struct CodepointRangePicker: View {
    @Binding var ranges: String
    @State private var editing = false

    var body: some View {
        Menu {
            Picker("Characters", selection: $ranges) {
                ForEach(CodepointRangeSet.presets) { Text($0.name).tag($0.ranges) }
                if !CodepointRangeSet.presets.contains(where: { $0.ranges == ranges }) {
                    Text(ranges).tag(ranges)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Custom Ranges…") { editing = true }
        } label: {
            Text(CodepointRangeSet.describe(ranges)).lineLimit(1).truncationMode(.tail)
        }
        .fixedSize()
        .help(ranges)
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Character Ranges").font(.headline)
                Text("Hexadecimal code points or ranges, separated by commas: U+E000-U+F8FF,U+1F600")
                    .font(.caption).foregroundStyle(.secondary)
                CommitField("U+E000-U+F8FF", text: ranges, width: 300, monospaced: true) { text in
                    let cleaned = text.replacingOccurrences(of: " ", with: "")
                    if !cleaned.isEmpty { ranges = cleaned }
                }
            }
            .padding()
        }
    }
}
