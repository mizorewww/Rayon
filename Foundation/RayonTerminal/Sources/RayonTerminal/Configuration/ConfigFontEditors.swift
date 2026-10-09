import AppKit
import CoreText
import RayonDesign
import SwiftUI

/// The fonts installed on this Mac, read once.
@MainActor
enum FontLibrary {
    struct Family: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let monospaced: Bool
    }

    static let families: [Family] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .map { name in
                let font = members(of: name).first.flatMap { NSFont(name: $0.postScriptName, size: 12) }
                let mono = font.map { $0.isFixedPitch || $0.fontDescriptor.symbolicTraits.contains(.monoSpace) } ?? false
                return Family(name: name, monospaced: mono)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static func isMonospaced(_ family: String) -> Bool {
        families.first { $0.name == family }?.monospaced ?? false
    }

    struct Member {
        let postScriptName: String
        let style: String
    }

    static func members(of family: String) -> [Member] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { entry in
            guard entry.count >= 2, let name = entry[0] as? String, let style = entry[1] as? String else { return nil }
            return Member(postScriptName: name, style: style)
        }
    }

    /// Style names offered when the family is Ghostty's built-in font.
    static let builtInStyles = ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]

    static func styles(of family: String) -> [String] {
        guard !family.isEmpty else { return builtInStyles }
        var seen = Set<String>()
        return members(of: family).map(\.style).filter { seen.insert($0).inserted }
    }

    struct Axis: Identifiable {
        var id: String { tag }
        let tag: String
        let name: String
        let minimum: Double
        let maximum: Double
        let defaultValue: Double
    }

    /// Variable-font axes (weight, width, slant…) of the family's first member.
    static func axes(of family: String) -> [Axis] {
        guard let member = members(of: family).first,
              let font = NSFont(name: member.postScriptName, size: 12),
              let raw = CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]]
        else { return [] }
        return raw.compactMap { axis in
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber else { return nil }
            let value = identifier.uint32Value
            let tag = String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }, encoding: .ascii) ?? "\(value)"
            return Axis(
                tag: tag,
                name: axis[kCTFontVariationAxisNameKey] as? String ?? tag,
                minimum: (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue ?? 0,
                maximum: (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue ?? 0,
                defaultValue: (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue ?? 0
            )
        }
    }
}

/// A button showing the chosen family in its own typeface; opens the font list.
struct ConfigFontPicker: View {
    /// Outer width shared by the font and style pickers so they line up.
    static let width: CGFloat = 224

    @Binding var family: String
    /// Shown when no family is set.
    let placeholder: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: RX.Space.s2) {
                Text(family.isEmpty ? placeholder : family)
                    .font(family.isEmpty ? .rxBody : .custom(family, size: 13))
                    .foregroundStyle(family.isEmpty ? Color.rxInkSecondary : Color.rxInk)
                    .lineLimit(1)
                Spacer(minLength: RX.Space.s2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.rxInkSecondary)
            }
            .frame(width: Self.width - 28)
        }
        .buttonStyle(.rx)
        .help("Choose a font installed on this Mac")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            FontFamilyList(selection: $family, placeholder: placeholder) { open = false }
        }
    }
}

/// Installed families, each drawn in its own typeface, with search and a
/// monospaced-only filter (on by default: terminals need fixed-width glyphs).
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
            (!monospacedOnly || family.monospaced)
                && (search.isEmpty || family.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            RXSearchField("Search fonts", text: $search, width: nil)
            Toggle("Monospaced fonts only", isOn: $monospacedOnly)
                .toggleStyle(.checkbox)
                .font(.rxHelp)
            ScrollViewReader { proxy in
                List {
                    row(name: "", title: placeholder, font: .rxBody)
                    ForEach(families) { family in
                        row(name: family.name, title: family.name, font: .custom(family.name, size: 14))
                            .id(family.name)
                    }
                }
                .listStyle(.plain)
                .onAppear { if !selection.isEmpty { proxy.scrollTo(selection, anchor: .center) } }
            }
            if families.isEmpty {
                HelpText("No installed font matches.")
            }
        }
        .padding(RX.Space.s3)
        .frame(width: 320, height: 420)
    }

    private func row(name: String, title: String, font: Font) -> some View {
        Button {
            selection = name
            done()
        } label: {
            HStack {
                Text(title).font(font).lineLimit(1)
                Spacer()
                if selection == name {
                    Image(systemName: "checkmark").foregroundStyle(.rxAccent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `font-family`: the main font, then fallbacks tried in order for missing glyphs.
struct ConfigFontFamilyEditor: View {
    @ObservedObject var model: ConfigEditorModel
    let key: String
    /// Bold / italic families may be left unset to follow the main font.
    let placeholder: String
    /// A fallback row being chosen; it reaches the document once a font is picked.
    @State private var addingFallback = false

    private var families: [String] { model.document.overrides[key] ?? [] }

    private func write(_ values: [String]) {
        let cleaned = values.filter { !$0.isEmpty }
        model.edit { document in
            if cleaned.isEmpty { document.overrides.removeValue(forKey: key) } else { document.set(key, cleaned) }
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: RX.Space.s2) {
            ConfigFontPicker(
                family: Binding(get: { families.first ?? "" }, set: { name in
                    var next = families
                    if next.isEmpty { next = [name] } else { next[0] = name }
                    write(next)
                }),
                placeholder: placeholder
            )
            ForEach(Array(families.enumerated().dropFirst()), id: \.offset) { index, _ in
                HStack(spacing: RX.Space.s1) {
                    Text("Fallback")
                        .font(.rxHelp)
                        .foregroundStyle(.rxInkSecondary)
                    ConfigFontPicker(
                        family: Binding(get: { families.indices.contains(index) ? families[index] : "" }, set: { name in
                            var next = families
                            guard next.indices.contains(index) else { return }
                            next[index] = name
                            write(next)
                        }),
                        placeholder: "Choose…"
                    )
                    RXIconButton("Remove Fallback", systemImage: "minus.circle", kind: .plain, size: .small) {
                        var next = families
                        guard next.indices.contains(index) else { return }
                        next.remove(at: index)
                        write(next)
                    }
                }
            }
            if addingFallback {
                HStack(spacing: RX.Space.s1) {
                    Text("Fallback")
                        .font(.rxHelp)
                        .foregroundStyle(.rxInkSecondary)
                    ConfigFontPicker(
                        family: Binding(get: { "" }, set: { name in
                            addingFallback = false
                            if !name.isEmpty { write(families + [name]) }
                        }),
                        placeholder: "Choose…"
                    )
                    RXIconButton("Cancel", systemImage: "minus.circle", kind: .plain, size: .small) {
                        addingFallback = false
                    }
                }
            } else if !families.isEmpty {
                Button {
                    addingFallback = true
                } label: {
                    Label("Add Fallback Font", systemImage: "plus")
                }
                .buttonStyle(.rx(.plain, size: .small))
                .fixedSize()
                .help("Used for characters the main font does not have")
            }
        }
    }
}

/// `font-style…`: the styles the chosen family actually has.
struct ConfigFontStylePicker: View {
    @ObservedObject var model: ConfigEditorModel
    let key: String

    /// The family this style applies to: its own family key, else the main font.
    private var family: String {
        let own = key.replacingOccurrences(of: "font-style", with: "font-family")
        return model.document.overrides[own]?.first ?? model.document.overrides["font-family"]?.first ?? ""
    }

    private func name(_ value: String) -> String {
        switch value {
        case "default", "": return "Default"
        case "false": return "Disabled (use regular)"
        default: return value
        }
    }

    var body: some View {
        let value = model.binding(key)
        let styles = FontLibrary.styles(of: family)
        Menu {
            Picker("Style", selection: value) {
                Text("Default").tag("default")
                if key != "font-style" {
                    Text("Disabled (use regular)").tag("false")
                }
                Divider()
                ForEach(styles, id: \.self) { Text($0).tag($0) }
                if !["default", "false", ""].contains(value.wrappedValue), !styles.contains(value.wrappedValue) {
                    Text(value.wrappedValue).tag(value.wrappedValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: RX.Space.s2) {
                Text(name(value.wrappedValue))
                    .font(.rxBody)
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                Spacer(minLength: RX.Space.s2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.rxInkSecondary)
            }
            .frame(width: ConfigFontPicker.width - 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.rx)
        .fixedSize()
        .help(family.isEmpty ? "Styles of the built-in font" : "Styles installed for \(family)")
    }
}

/// Quick inserts for list settings whose values follow a small vocabulary.
struct ConfigListSuggestions: View {
    @ObservedObject var model: ConfigEditorModel
    let key: String

    private struct Suggestion: Hashable {
        let value: String
        let title: String
    }

    private var suggestions: [Suggestion] {
        switch key {
        case "font-feature":
            return [
                .init(value: "-calt", title: "Turn off ligatures (-calt)"),
                .init(value: "-liga", title: "Turn off standard ligatures (-liga)"),
                .init(value: "-dlig", title: "Turn off discretionary ligatures (-dlig)"),
                .init(value: "zero", title: "Slashed zero (zero)"),
                .init(value: "ss01", title: "Stylistic set 1 (ss01)"),
                .init(value: "ss02", title: "Stylistic set 2 (ss02)"),
                .init(value: "ss03", title: "Stylistic set 3 (ss03)"),
                .init(value: "cv01", title: "Character variant 1 (cv01)"),
            ]
        case "font-variation", "font-variation-bold", "font-variation-italic", "font-variation-bold-italic":
            let own = key.replacingOccurrences(of: "font-variation", with: "font-family")
            let family = model.document.overrides[own]?.first ?? model.document.overrides["font-family"]?.first ?? ""
            return FontLibrary.axes(of: family).map { axis in
                .init(
                    value: "\(axis.tag)=\(axis.defaultValue.formatted())",
                    title: "\(axis.name) (\(axis.tag), \(axis.minimum.formatted())–\(axis.maximum.formatted()))"
                )
            }
        default:
            return []
        }
    }

    var body: some View {
        let options = suggestions
        let current = Set(model.document.values(key))
        Menu {
            if options.isEmpty {
                Text(key.hasPrefix("font-variation") ? "The chosen font has no variation axes" : "No suggestions")
            }
            ForEach(options, id: \.self) { option in
                Button(option.title) { model.edit { $0.set(key, $0.values(key) + [option.value]) } }
                    .disabled(current.contains(option.value))
            }
        } label: {
            Label(key.hasPrefix("font-variation") ? "Add Axis" : "Add Feature", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.rx(size: .small))
        .fixedSize()
    }
}

/// A byte count edited in megabytes.
struct ConfigByteInput: View {
    @Binding var value: String
    let fallback: String

    private var megabytes: Double { (Double(value.isEmpty ? fallback : value) ?? 0) / 1_000_000 }

    var body: some View {
        HStack(spacing: RX.Space.s1) {
            TextField("MB", value: Binding(get: { megabytes }, set: { value = String(Int(max(0, $0) * 1_000_000)) }), format: .number.precision(.fractionLength(0 ... 1)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.rx)
                .frame(width: 96)
            Stepper("Megabytes", onIncrement: { value = String(Int((megabytes + 1) * 1_000_000)) },
                    onDecrement: { value = String(Int(max(0, megabytes - 1) * 1_000_000)) })
                .labelsHidden()
            Text("MB")
                .font(.rxBody)
                .foregroundStyle(.rxInkSecondary)
        }
    }
}
