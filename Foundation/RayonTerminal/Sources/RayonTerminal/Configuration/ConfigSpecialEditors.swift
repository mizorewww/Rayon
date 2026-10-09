import RayonDesign
import SwiftUI

struct ConfigThemePicker: View {
    @Binding var value: String
    @State private var search = ""
    @State private var darkSide = false
    private var dual: Bool { value.hasPrefix("light:") && value.contains(",dark:") }
    private var selected: String {
        guard dual else { return value }
        return value.components(separatedBy: ",")[darkSide ? 1 : 0].components(separatedBy: ":").dropFirst().joined(separator: ":")
    }
    private func select(_ name: String) {
        if dual {
            var parts = value.components(separatedBy: ",")
            parts[darkSide ? 1 : 0] = (darkSide ? "dark:" : "light:") + name
            value = parts.joined(separator: ",")
        } else { value = name }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(spacing: RX.Space.s3) {
                Toggle("Separate light and dark themes", isOn: Binding(get: { dual }, set: { enabled in value = enabled ? "light:\(value),dark:\(value)" : selected }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.rxAccent)
                    .font(.rxBody)
                if dual {
                    RXSegmented(selection: $darkSide, options: [.init(false, "Light"), .init(true, "Dark")], caps: false)
                }
                Spacer()
            }
            HStack(spacing: RX.Space.s2) {
                TextField("Theme name, path, or light:Name,dark:Name", text: $value)
                    .textFieldStyle(.rxMono)
                RXSearchField("Search themes", text: $search, width: 200)
            }
            if !selected.isEmpty && ConfigCatalog.shared.themes[selected] == nil {
                HelpText("Only bundled themes can be applied.")
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: RX.Space.s2)], spacing: RX.Space.s2) {
                    ForEach(ConfigCatalog.shared.themeNames.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { name in
                        let theme = ConfigCatalog.shared.themes[name]!
                        Button { select(name) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                HStack(spacing: 2) {
                                    ForEach(0 ..< min(theme.palette.count, 8), id: \.self) { i in
                                        Rectangle().fill(Color(configHex: theme.palette[i])).frame(height: 8)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                Text("❯ rayon ~/project").font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundStyle(Color(configHex: theme.foreground ?? "#ffffff"))
                            .padding(10)
                            .background(Color(configHex: theme.background ?? "#000000"), in: RoundedRectangle(cornerRadius: RX.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RX.Radius.md, style: .continuous)
                                    .strokeBorder(selected == name ? Color.rxAccent : Color.rxHairline, lineWidth: selected == name ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }
                .padding(3)
            }
            .frame(height: 280)
        }
    }
}

/// The 16 (or 256) palette swatches: a color well, its hex value and a reset.
struct ConfigPaletteEditor: View {
    @ObservedObject var model: ConfigEditorModel
    @Environment(\.colorScheme) private var scheme
    @State private var extended = false
    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            Toggle("Show all 256 colors", isOn: $extended)
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.rxAccent)
                .font(.rxBody)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: RX.Space.s2)], spacing: RX.Space.s2) {
                ForEach(0 ..< (extended ? 256 : 16), id: \.self) { index in
                    HStack(spacing: 6) {
                        Text("\(index)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.rxInkSecondary)
                            .frame(width: 22, alignment: .trailing)
                        ColorPicker("Color \(index)", selection: Binding(get: { Color(configHex: model.document.effectivePalette(index, dark: scheme == .dark)) }, set: { color in model.edit { $0.setPalette(index, color: color.configHex) } }), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40)
                        TextField("Color", text: Binding(get: { model.document.effectivePalette(index, dark: scheme == .dark) }, set: { color in model.edit { $0.setPalette(index, color: color) } }))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                        RXIconButton("Reset Color \(index)", systemImage: "arrow.counterclockwise", kind: .plain, size: .small) {
                            model.edit { $0.setPalette(index, color: nil) }
                        }
                        .disabled(model.document.paletteOverrides[index] == nil)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: RX.Radius.md, style: .continuous).fill(Color.rxSurfaceSunken))
                }
            }
        }
    }
}

struct ConfigKeybindingList: View {
    @ObservedObject var model: ConfigEditorModel
    @State private var selected: Set<Int> = []
    @State private var editIndex: Int?
    @State private var raw = "super+k=ignore"
    @State private var editing = false
    @State private var filter = ""
    @State private var confirmReset = false
    private var entries: [String] { model.document.values("keybind") }
    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(spacing: RX.Space.s2) {
                RXSearchField("Search bindings", text: $filter, width: 220)
                Spacer()
                Button("Delete Selected") {
                    model.edit { $0.set("keybind", entries.enumerated().filter { !selected.contains($0.offset) }.map(\.element)) }
                    selected.removeAll()
                }
                .buttonStyle(.rx)
                .disabled(selected.isEmpty)
                Button("Reset…") { confirmReset = true }
                    .buttonStyle(.rx)
                Button {
                    editIndex = nil; raw = "super+k=ignore"; editing = true
                } label: {
                    Label("New Keybinding", systemImage: "plus")
                }
                .buttonStyle(.rxPrimary)
            }
            RXDividedStack {
                ForEach(Array(entries.enumerated()).filter { filter.isEmpty || $0.element.localizedCaseInsensitiveContains(filter) }, id: \.offset) { index, entry in
                    let parsed = ConfigKeybinding(entry)
                    HStack(spacing: RX.Space.s3) {
                        Toggle("Select", isOn: Binding(get: { selected.contains(index) }, set: { if $0 { selected.insert(index) } else { selected.remove(index) } }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry)
                                .font(.rxCode)
                                .foregroundStyle(.rxInk)
                                .textSelection(.enabled)
                                .lineLimit(2)
                            if !parsed.errors.isEmpty {
                                HelpText(parsed.errors.joined(separator: "; "), isError: true)
                            }
                        }
                        Spacer()
                        if entries.filter({ ConfigKeybinding($0).canonical == parsed.canonical }).count > 1 {
                            RXTag("Duplicate trigger", style: .warning)
                        }
                        Button("Edit") { editIndex = index; raw = entry; editing = true }
                            .buttonStyle(.rx(size: .small))
                    }
                    .padding(.vertical, 6)
                    .frame(minHeight: RX.tableRowHeight)
                }
            }
            .padding(.horizontal, RX.Space.s4)
            .background(Color.clear.rxCard(padding: 0))
        }
        .confirmationDialog("Reset all keybindings to their defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.reset("keybind") }
        }
        .sheet(isPresented: $editing) {
            ConfigKeybindingBuilder(raw: $raw) {
                model.edit { doc in
                    var values = doc.values("keybind")
                    if let editIndex, values.indices.contains(editIndex) { values[editIndex] = raw } else { values.append(raw) }
                    doc.set("keybind", values)
                }
                editing = false
            }
        }
    }
}

struct ConfigKeybindingBuilder: View {
    @Binding var raw: String
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var parsed: ConfigKeybinding { ConfigKeybinding(raw) }
    private func edit(_ mutation: (inout ConfigKeybinding) -> Void) { var next = parsed; mutation(&next); raw = next.rendered }
    var body: some View {
        SheetScaffold("Keybinding") {
            VStack(alignment: .leading, spacing: 14) {
                RXField("Scope") {
                    RXFlowLayout(spacing: 6) {
                        ForEach(["all", "global", "unconsumed", "performable"], id: \.self) { prefix in
                            RXChip(prefix, isOn: parsed.prefixes.contains(prefix)) {
                                edit {
                                    if $0.prefixes.contains(prefix) {
                                        $0.prefixes.removeAll { $0 == prefix }
                                    } else {
                                        $0.prefixes.append(prefix)
                                        if prefix == "all" || prefix == "global" { $0.steps = Array($0.steps.prefix(1)) }
                                    }
                                }
                            }
                        }
                    }
                }
                ForEach(Array(parsed.steps.enumerated()), id: \.offset) { index, _ in
                    RXField(parsed.steps.count > 1 ? "Trigger · step \(index + 1)" : "Trigger") {
                        VStack(alignment: .leading, spacing: RX.Space.s2) {
                            HStack(spacing: RX.Space.s2) {
                                TextField("super+k", text: Binding(get: { parsed.steps.indices.contains(index) ? parsed.steps[index] : "" }, set: { text in edit { $0.steps[index] = text } }))
                                    .textFieldStyle(.rxMono)
                                Menu("Key") {
                                    ForEach(ConfigKeybindingCatalog.shared.keys, id: \.self) { key in Button(key) { edit { $0.steps[index] = key } } }
                                }
                                .fixedSize()
                                if parsed.steps.count > 1 {
                                    Button("Remove") { edit { $0.steps.remove(at: index) } }
                                        .buttonStyle(.rx)
                                }
                            }
                            RXFlowLayout(spacing: 6) {
                                ForEach(["super", "ctrl", "alt", "shift"], id: \.self) { modifier in
                                    RXChip(modifier, isOn: ConfigKeybinding.splitStep(parsed.steps[index]).0.contains(modifier)) {
                                        edit {
                                            var (modifiers, key) = ConfigKeybinding.splitStep($0.steps[index])
                                            if modifiers.contains(modifier) { modifiers.removeAll { $0 == modifier } } else { modifiers.append(modifier) }
                                            $0.steps[index] = (modifiers.sorted() + [key]).joined(separator: "+")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Add Sequence Step") { edit { $0.steps.append("k") } }
                    .buttonStyle(.rx)
                    .disabled(parsed.steps.count >= 4 || parsed.prefixes.contains("all") || parsed.prefixes.contains("global"))
                RXField("Action") {
                    Picker("Action", selection: Binding(get: { parsed.action }, set: { name in edit { $0.action = name; $0.argument = nil } })) {
                        ForEach(ConfigKeybindingCatalog.shared.actions.filter { RayonTerminalConfiguration.supportedActions.contains($0.name) }) { action in
                            Text(action.name).tag(action.name)
                        }
                    }
                    .labelsHidden()
                }
                if let action = ConfigKeybindingCatalog.shared.actions.first(where: { $0.name == parsed.action }) {
                    if let description = action.description { HelpText(description) }
                    if let options = action.options {
                        RXField("Argument") {
                            Picker("Argument", selection: Binding(get: { parsed.argument ?? "" }, set: { arg in edit { $0.argument = arg.isEmpty ? nil : arg } })) {
                                Text("None").tag(""); ForEach(options, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                    } else if action.type != "none" {
                        RXField("Argument") {
                            TextField("Argument", text: Binding(get: { parsed.argument ?? "" }, set: { arg in edit { $0.argument = arg } }))
                                .textFieldStyle(.rxMono)
                        }
                    }
                }
                RXField("Raw binding", error: parsed.errors.isEmpty ? nil : parsed.errors.joined(separator: "\n")) {
                    TextField("Raw binding", text: $raw)
                        .textFieldStyle(.rxMono)
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
                .disabled(!parsed.errors.isEmpty)
        }
        .frame(width: 580)
    }
}
