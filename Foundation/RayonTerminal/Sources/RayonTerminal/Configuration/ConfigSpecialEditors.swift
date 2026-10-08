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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Light / dark pair", isOn: Binding(get: { dual }, set: { enabled in value = enabled ? "light:\(value),dark:\(value)" : selected }))
                if dual { Picker("Mode", selection: $darkSide) { Text("Light").tag(false); Text("Dark").tag(true) }.pickerStyle(.segmented).frame(width: 160) }
            }
            TextField("Theme name, path, or light:Name,dark:Name", text: $value)
            if !selected.isEmpty && ConfigCatalog.shared.themes[selected] == nil {
                Text("Custom theme name/path is preserved for export. Only bundled themes can be previewed and applied in Rayon.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Search 633 themes", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 8) {
                    ForEach(ConfigCatalog.shared.themes.keys.sorted().filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { name in
                        let theme = ConfigCatalog.shared.themes[name]!
                        Button { select(name) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(name).font(.caption).lineLimit(1)
                                HStack(spacing: 2) { ForEach(0..<min(theme.palette.count, 8), id: \.self) { i in Rectangle().fill(Color(configHex: theme.palette[i])).frame(height: 8) } }
                                Text("❯ rayon ~/project").font(.system(size: 10, design: .monospaced))
                            }.foregroundStyle(Color(configHex: theme.foreground ?? "#ffffff"))
                                .padding(10).background(Color(configHex: theme.background ?? "#000000"), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected == name ? Color.accentColor : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }.padding(3)
            }.frame(height: 260)
        }
    }
}
struct ConfigPaletteEditor: View {
    @ObservedObject var model: ConfigEditorModel
    @Environment(\.colorScheme) private var scheme
    @State private var extended = false
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Show all 256 colors", isOn: $extended)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                ForEach(0..<(extended ? 256 : 16), id: \.self) { index in
                    VStack {
                        HStack {
                            Text("\(index)").font(.caption.monospacedDigit())
                            ColorPicker("Color \(index)", selection: Binding(get: { Color(configHex: model.document.effectivePalette(index, dark: scheme == .dark)) }, set: { color in model.edit { $0.setPalette(index, color: color.configHex) } }), supportsOpacity: false).labelsHidden()
                            Button { model.edit { $0.setPalette(index, color: nil) } } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.borderless).disabled(model.document.paletteOverrides[index] == nil)
                        }
                        TextField("Color", text: Binding(get: { model.document.effectivePalette(index, dark: scheme == .dark) }, set: { color in model.edit { $0.setPalette(index, color: color) } })).font(.system(.caption, design: .monospaced))
                    }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search bindings", text: $filter)
                Button("Add") { editIndex = nil; raw = "super+k=ignore"; editing = true }
                Button("Delete selected") { model.edit { $0.set("keybind", entries.enumerated().filter { !selected.contains($0.offset) }.map(\.element)) }; selected.removeAll() }.disabled(selected.isEmpty)
                Button("Reset") { confirmReset = true }
            }
            Text("Terminal input and scrolling actions can be applied in Rayon. Window, tab, global and application actions are exported for standalone Ghostty.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(entries.enumerated()).filter { filter.isEmpty || $0.element.localizedCaseInsensitiveContains(filter) }, id: \.offset) { index, entry in
                let parsed = ConfigKeybinding(entry)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle("Select", isOn: Binding(get: { selected.contains(index) }, set: { if $0 { selected.insert(index) } else { selected.remove(index) } })).labelsHidden()
                        Text(entry).font(.system(.body, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("Edit") { editIndex = index; raw = entry; editing = true }
                    }
                    if !parsed.errors.isEmpty { Text(parsed.errors.joined(separator: "; ")).font(.caption).foregroundStyle(.red) }
                    if entries.filter({ ConfigKeybinding($0).canonical == parsed.canonical }).count > 1 {
                        Text("Duplicate trigger").font(.caption).foregroundStyle(.orange)
                    }
                }.padding(8).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .confirmationDialog("Reset all keybindings to defaults?", isPresented: $confirmReset) { Button("Reset", role: .destructive) { model.reset("keybind") } }
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Keybinding Builder").font(.title2.bold())
            HStack {
                ForEach(["all", "global", "unconsumed", "performable"], id: \.self) { prefix in
                    Toggle(prefix, isOn: Binding(get: { parsed.prefixes.contains(prefix) }, set: { enabled in edit {
                        if enabled { $0.prefixes.append(prefix); if prefix == "all" || prefix == "global" { $0.steps = Array($0.steps.prefix(1)) } }
                        else { $0.prefixes.removeAll { $0 == prefix } }
                    } }))
                }
            }
            ForEach(Array(parsed.steps.enumerated()), id: \.offset) { index, _ in
                VStack(alignment: .leading) {
                HStack {
                    Text("Step \(index + 1)")
                    TextField("super+k", text: Binding(get: { parsed.steps.indices.contains(index) ? parsed.steps[index] : "" }, set: { text in edit { $0.steps[index] = text } }))
                    Menu("Key") { ForEach(ConfigKeybindingCatalog.shared.keys, id: \.self) { key in Button(key) { edit { $0.steps[index] = key } } } }
                    if parsed.steps.count > 1 { Button("Remove") { edit { $0.steps.remove(at: index) } } }
                }
                HStack {
                    ForEach(["super", "ctrl", "alt", "shift"], id: \.self) { modifier in
                        Toggle(modifier, isOn: Binding(get: {
                            ConfigKeybinding.splitStep(parsed.steps[index]).0.contains(modifier)
                        }, set: { enabled in edit {
                            var (modifiers, key) = ConfigKeybinding.splitStep($0.steps[index])
                            modifiers.removeAll { $0 == modifier }
                            if enabled { modifiers.append(modifier) }
                            $0.steps[index] = (modifiers.sorted() + [key]).joined(separator: "+")
                        } }))
                    }
                }.font(.caption)
                }
            }
            Button("Add sequence step") { edit { $0.steps.append("k") } }
                .disabled(parsed.steps.count >= 4 || parsed.prefixes.contains("all") || parsed.prefixes.contains("global"))
            Picker("Action", selection: Binding(get: { parsed.action }, set: { name in edit { $0.action = name; $0.argument = nil } })) {
                ForEach(ConfigKeybindingCatalog.shared.actions) { action in Text(action.name).tag(action.name) }
            }
            if let action = ConfigKeybindingCatalog.shared.actions.first(where: { $0.name == parsed.action }) {
                Text(action.description ?? "").font(.caption).foregroundStyle(.secondary)
                if let options = action.options {
                    Picker("Argument", selection: Binding(get: { parsed.argument ?? "" }, set: { arg in edit { $0.argument = arg.isEmpty ? nil : arg } })) {
                        Text("None").tag(""); ForEach(options, id: \.self) { Text($0).tag($0) }
                    }
                } else if action.type != "none" {
                    TextField("Argument", text: Binding(get: { parsed.argument ?? "" }, set: { arg in edit { $0.argument = arg } }))
                }
            }
            TextField("Raw binding", text: $raw).font(.system(.body, design: .monospaced))
            Text(parsed.errors.joined(separator: "\n")).foregroundStyle(.red).font(.caption)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!parsed.errors.isEmpty) }
        }.padding(24).frame(width: 580)
    }
}
