import RayonDesign
import SwiftUI

/// A named set of Unicode ranges, as Ghostty writes them (`U+E000-U+F8FF,U+F0000`).
struct CodepointRangeSet: Identifiable, Hashable {
    var id: String { ranges }
    let name: String
    let ranges: String

    static let presets: [CodepointRangeSet] = [
        .init(name: "Nerd Font icons", ranges: "U+E000-U+F8FF,U+F0000-U+FFFFD"),
        .init(name: "Powerline symbols", ranges: "U+E0A0-U+E0D4"),
        .init(name: "Chinese, Japanese and Korean characters", ranges: "U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,U+20000-U+2FA1F"),
        .init(name: "Japanese kana", ranges: "U+3040-U+30FF,U+31F0-U+31FF"),
        .init(name: "Korean Hangul", ranges: "U+1100-U+11FF,U+3130-U+318F,U+AC00-U+D7AF"),
        .init(name: "CJK punctuation and full-width forms", ranges: "U+3000-U+303F,U+FF00-U+FFEF"),
        .init(name: "Emoji", ranges: "U+2600-U+27BF,U+1F300-U+1FAFF"),
        .init(name: "Box drawing and blocks", ranges: "U+2500-U+259F"),
        .init(name: "Braille", ranges: "U+2800-U+28FF"),
        .init(name: "Arrows", ranges: "U+2190-U+21FF"),
        .init(name: "Mathematical operators", ranges: "U+2200-U+22FF"),
        .init(name: "Greek", ranges: "U+0370-U+03FF"),
        .init(name: "Cyrillic", ranges: "U+0400-U+04FF"),
        .init(name: "Hebrew", ranges: "U+0590-U+05FF"),
        .init(name: "Arabic", ranges: "U+0600-U+06FF"),
        .init(name: "Devanagari", ranges: "U+0900-U+097F"),
        .init(name: "Thai", ranges: "U+0E00-U+0E7F"),
    ]

    /// A preset's name, or the ranges themselves for a custom set.
    static func describe(_ ranges: String) -> String {
        presets.first { $0.ranges.caseInsensitiveCompare(ranges) == .orderedSame }?.name ?? ranges
    }
}

/// One `font-codepoint-map` entry: `ranges=Family`.
struct CodepointMapping: Equatable {
    var ranges: String
    var family: String

    init(ranges: String, family: String) {
        self.ranges = ranges
        self.family = family
    }

    init?(_ entry: String) {
        guard let eq = entry.lastIndex(of: "=") else { return nil }
        ranges = entry[..<eq].trimmingCharacters(in: .whitespaces)
        family = entry[entry.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    }

    var rendered: String { "\(ranges)=\(family)" }
}

/// `font-codepoint-map`: "these characters use this font", one row per rule,
/// with named character sets and the installed-font picker.
struct ConfigCodepointMapEditor: View {
    @ObservedObject var model: ConfigEditorModel
    /// A rule being added; it is written once it has a font.
    @State private var pending: CodepointMapping?

    private var entries: [String] { model.document.overrides["font-codepoint-map"] ?? [] }

    private func write(_ values: [String]) {
        model.edit { document in
            if values.isEmpty { document.overrides.removeValue(forKey: "font-codepoint-map") } else { document.set("font-codepoint-map", values) }
        }
    }

    private func update(_ index: Int, _ change: (inout CodepointMapping) -> Void) {
        var values = entries
        guard values.indices.contains(index), var mapping = CodepointMapping(values[index]) else { return }
        change(&mapping)
        values[index] = mapping.rendered
        write(values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                if let mapping = CodepointMapping(entry) {
                    row(
                        ranges: Binding(get: { mapping.ranges }, set: { ranges in update(index) { $0.ranges = ranges } }),
                        family: Binding(get: { mapping.family }, set: { family in update(index) { $0.family = family } }),
                        remove: { write(entries.enumerated().filter { $0.offset != index }.map(\.element)) }
                    )
                } else {
                    HStack {
                        Text(entry).font(.rxCode).foregroundStyle(.rxInkSecondary)
                        Spacer()
                        RXIconButton("Remove Rule", systemImage: "minus.circle", kind: .plain, size: .small) {
                            write(entries.enumerated().filter { $0.offset != index }.map(\.element))
                        }
                    }
                }
            }
            if let pending {
                row(
                    ranges: Binding(get: { pending.ranges }, set: { self.pending?.ranges = $0 }),
                    family: Binding(get: { "" }, set: { family in
                        guard !family.isEmpty else { return }
                        write(entries + [CodepointMapping(ranges: pending.ranges, family: family).rendered])
                        self.pending = nil
                    }),
                    remove: { self.pending = nil }
                )
            } else {
                Button {
                    pending = CodepointMapping(ranges: CodepointRangeSet.presets[0].ranges, family: "")
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.rx(size: .small))
                .fixedSize()
            }
        }
    }

    private func row(ranges: Binding<String>, family: Binding<String>, remove: @escaping () -> Void) -> some View {
        HStack(spacing: RX.Space.s2) {
            CodepointRangePicker(ranges: ranges)
            Text("use")
                .font(.rxHelp)
                .foregroundStyle(.rxInkSecondary)
            ConfigFontPicker(family: family, placeholder: "Choose a font…")
            RXIconButton("Remove Rule", systemImage: "minus.circle", kind: .plain, size: .small, action: remove)
        }
    }
}

/// A named character set, or custom ranges edited as From / To pairs.
private struct CodepointRangePicker: View {
    @Binding var ranges: String
    @State private var editing = false

    var body: some View {
        Menu {
            ForEach(CodepointRangeSet.presets) { preset in
                Button {
                    ranges = preset.ranges
                } label: {
                    if preset.ranges == ranges {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
            Divider()
            Button("Custom Ranges…") { editing = true }
        } label: {
            HStack(spacing: RX.Space.s2) {
                Text(CodepointRangeSet.describe(ranges))
                    .font(.rxBody)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: RX.Space.s1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.rxInkSecondary)
            }
            .frame(width: 220)
        }
        .rxButtonMenu(indicator: false)
        .buttonStyle(.rx)
        .fixedSize()
        .help(ranges)
        .popover(isPresented: $editing) {
            CodepointRangeEditor(ranges: $ranges)
        }
    }
}

/// Custom ranges as rows of hexadecimal From and To code points.
private struct CodepointRangeEditor: View {
    @Binding var ranges: String
    @State private var rows: [(from: String, to: String)] = []

    private static func parse(_ text: String) -> [(from: String, to: String)] {
        text.split(separator: ",").map { part in
            let bounds = part.split(separator: "-").map {
                $0.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "U+", with: "")
            }
            return (bounds.first ?? "", bounds.count > 1 ? bounds[1] : "")
        }
    }

    private func commit() {
        let valid = rows.filter { UInt32($0.from, radix: 16) != nil }
        let text = valid.map { row in
            UInt32(row.to, radix: 16) == nil || row.to.isEmpty ? "U+\(row.from)" : "U+\(row.from)-U+\(row.to)"
        }.joined(separator: ",")
        if !text.isEmpty { ranges = text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            Text("Character Ranges").font(.rxBodyStrong)
            HelpText("Hexadecimal code points; leave To empty for a single character.")
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: RX.Space.s1) {
                    Text("U+").font(.rxCode).foregroundStyle(.rxInkSecondary)
                    TextField("E000", text: Binding(get: { rows.indices.contains(index) ? rows[index].from : "" }, set: { guard rows.indices.contains(index) else { return }; rows[index].from = $0.uppercased(); commit() }))
                        .textFieldStyle(.rxMono)
                        .frame(width: 80)
                    Text("to U+").font(.rxCode).foregroundStyle(.rxInkSecondary)
                    TextField("F8FF", text: Binding(get: { rows.indices.contains(index) ? rows[index].to : "" }, set: { guard rows.indices.contains(index) else { return }; rows[index].to = $0.uppercased(); commit() }))
                        .textFieldStyle(.rxMono)
                        .frame(width: 80)
                    RXIconButton("Remove Range", systemImage: "minus.circle", kind: .plain, size: .small) {
                        rows.remove(at: index)
                        commit()
                    }
                    .disabled(rows.count == 1)
                }
            }
            Button {
                rows.append(("", ""))
            } label: {
                Label("Add Range", systemImage: "plus")
            }
            .buttonStyle(.rx(size: .small))
        }
        .padding(RX.Space.s4)
        .frame(width: 360)
        .onAppear { rows = Self.parse(ranges) }
    }
}
