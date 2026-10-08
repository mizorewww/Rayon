import SwiftUI
import AppKit

struct ConfigSettingRow: View {
    @ObservedObject var model: ConfigEditorModel
    let setting: ConfigSetting
    var query = ""
    private var highlightedName: AttributedString {
        var text = AttributedString(setting.name)
        for token in query.split(whereSeparator: \.isWhitespace) {
            if let range = text.range(of: String(token), options: .caseInsensitive) { text[range].foregroundColor = .accentColor; text[range].underlineStyle = .single }
        }
        return text
    }
    @State private var help = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(highlightedName).font(.headline)
                if model.document.overrides[setting.key] != nil { Circle().fill(Color.accentColor).frame(width: 6, height: 6).help("Modified") }
                Spacer()
                Button { help.toggle() } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.borderless)
                    .popover(isPresented: $help) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(setting.name).font(.title2)
                                Text(.init(setting.description))
                                Link("Ghostty documentation", destination: URL(string: "https://ghostty.org/docs/config/reference#" + setting.key)!)
                            }.padding().frame(width: 430)
                        }.frame(maxHeight: 500)
                    }
                Button { model.reset(setting.key) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless).disabled(model.document.overrides[setting.key] == nil).help("Reset to default")
            }
            HStack(spacing: 8) {
                Text(setting.key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                if let platform = setting.platform { Text(platform.joined(separator: " / ")) }
                if let since = setting.since { Text("≥ \(since)") }
                if setting.deprecated != nil { Text("Deprecated").foregroundStyle(.orange) }
            }.font(.caption).foregroundStyle(.secondary)
            if let note = setting.note {
                Text(note.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)).font(.caption).foregroundStyle(.secondary)
            }
            ConfigWidgetView(model: model, setting: setting).disabled(setting.disabled == true)
            if !RayonTerminalConfiguration.supportedKeys.contains(setting.key) {
                Text("Standalone Ghostty · editable and exported; managed separately by Rayon.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
    }
}

struct ConfigWidgetView: View {
    @ObservedObject var model: ConfigEditorModel
    let setting: ConfigSetting
    @Environment(\.colorScheme) private var scheme
    private var value: Binding<String> { model.binding(setting.key) }
    private var widget: ConfigWidget? { setting.widget }
    @ViewBuilder var body: some View {
        switch widget?.type ?? (setting.repeatable == true ? "repeatable-text" : "text") {
        case "switch":
            Toggle("Enabled", isOn: Binding(get: { value.wrappedValue.lowercased() == "true" }, set: { value.wrappedValue = String($0) })).toggleStyle(.switch)
        case "range":
            HStack {
                Slider(value: Binding(get: { Double(value.wrappedValue) ?? widget?.min ?? 0 }, set: { value.wrappedValue = String(format: "%g", $0) }),
                       in: (widget?.min ?? 0)...(widget?.max ?? 1), step: widget?.step ?? 0.01)
                TextField("Value", text: value).frame(width: 75)
            }
        case "dropdown", "pill":
            HStack {
                Picker("Value", selection: value) {
                    Text("Default / Unset").tag("")
                    ForEach(widget?.options ?? []) { option in Text(option.name).tag(option.value).disabled(option.disabled == true) }
                    if !value.wrappedValue.isEmpty && !(widget?.options ?? []).contains(where: { $0.value == value.wrappedValue }) { Text(value.wrappedValue).tag(value.wrappedValue) }
                }.labelsHidden()
                TextField("Custom value", text: value).frame(maxWidth: 200)
            }
        case "color": colorInput
        case "custom-color", "custom-number":
            HStack {
                Menu("Presets") {
                    ForEach(widget?.presets ?? []) { option in Button(option.name) { value.wrappedValue = option.value } }
                }.fixedSize()
                if widget?.type == "custom-color" { colorInput } else { numericInput }
            }
        case "number": numericInput
        case "theme": ConfigThemePicker(value: value)
        case "palette": ConfigPaletteEditor(model: model)
        case "repeatable-text": ConfigRepeatableEditor(model: model, key: setting.key)
        case "feature-list":
            VStack(alignment: .leading) {
                ForEach(widget?.features ?? []) { feature in
                    Toggle(feature.label, isOn: Binding(get: { featureValue(feature) }, set: { enabled in
                        var state = Dictionary(uniqueKeysWithValues: (widget?.features ?? []).map { ($0.id, featureValue($0)) })
                        state[feature.id] = enabled
                        value.wrappedValue = (widget?.features ?? []).filter { state[$0.id] != $0.defaultValue }
                            .map { state[$0.id] == true ? $0.id : "no-" + $0.id }.joined(separator: ",")
                    })).help(feature.description ?? "")
                }
                TextField("Raw value", text: value)
            }
        case "dual-number", "scroll-multiplier": ConfigPairInput(value: value, scroll: widget?.type == "scroll-multiplier", labels: widget?.labels ?? ["First", "Second"])
        case "duration": ConfigDurationInput(value: value, allowEmpty: widget?.allowEmpty == true)
        case "number-units": ConfigUnitInput(value: value, units: ["px", "%"])
        default:
            if setting.key == "keybind" { ConfigKeybindingList(model: model) }
            else { TextField(widget?.placeholder ?? "Value (empty uses default)", text: value).textFieldStyle(.roundedBorder) }
        }
    }
    private var numericInput: some View {
        HStack {
            TextField(widget?.placeholder ?? "Default", text: value).frame(maxWidth: 160)
            Stepper("Adjust", onIncrement: { step(1) }, onDecrement: { step(-1) }).labelsHidden()
            if let min = widget?.min { Text("min \(min.formatted())").font(.caption).foregroundStyle(.secondary) }
            if let max = widget?.max { Text("max \(max.formatted())").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func step(_ sign: Double) {
        let next = min(widget?.max ?? .greatestFiniteMagnitude, max(widget?.min ?? -.greatestFiniteMagnitude,
            (Double(value.wrappedValue) ?? 0) + sign * (widget?.step ?? 1)))
        value.wrappedValue = String(format: "%g", next)
    }
    private var colorInput: some View {
        HStack {
            ColorPicker("Color", selection: Binding(get: { Color(configHex: model.document.effectiveColor(setting.key, dark: scheme == .dark)) }, set: { value.wrappedValue = $0.configHex }), supportsOpacity: false).labelsHidden()
            TextField("#RRGGBB or named color", text: Binding(get: {
                widget?.type == "color" ? model.document.effectiveColor(setting.key, dark: scheme == .dark) : value.wrappedValue
            }, set: { value.wrappedValue = $0 })).textFieldStyle(.roundedBorder)
            Text(model.document.overrides[setting.key] != nil ? "Override" : model.document.effectiveTheme(dark: scheme == .dark) != nil ? "Theme" : "Default").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func featureValue(_ feature: ConfigFeature) -> Bool {
        let raw = value.wrappedValue
        if raw == "true" || raw == "false" { return raw == "true" }
        var result = feature.defaultValue
        for token in raw.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if token == feature.id { result = true }; if token == "no-" + feature.id { result = false }
        }
        return result
    }
}

extension Color {
    init(configHex: String) {
        let raw = configHex.replacingOccurrences(of: "#", with: "")
        if raw.count == 6, let n = UInt64(raw, radix: 16) {
            self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
        } else { self = configHex == "white" ? .white : .black }
    }
    var configHex: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

struct ConfigUnitInput: View {
    @Binding var value: String
    let units: [String]
    private var unit: String { units.first(where: { value.hasSuffix($0) }) ?? units[0] }
    private var number: String { units.first(where: { value.hasSuffix($0) }).map { String(value.dropLast($0.count)) } ?? value }
    var body: some View {
        HStack {
            TextField("Default", text: Binding(get: { number }, set: { value = $0.isEmpty ? "" : $0 + (unit == "px" ? "" : unit) })).frame(width: 130)
            Picker("Unit", selection: Binding(get: { unit }, set: { value = number.isEmpty ? "" : number + ($0 == "px" ? "" : $0) })) {
                ForEach(units, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 85)
            TextField("Raw value", text: $value).help("Preserves compound durations and custom values")
        }
    }
}
struct ConfigPairInput: View {
    @Binding var value: String
    let scroll: Bool
    let labels: [String]
    private var parts: [String] { ConfigPairCodec.parse(value, scroll: scroll).values }
    private var linked: Bool { ConfigPairCodec.parse(value, scroll: scroll).linked }
    var body: some View {
        HStack {
            TextField(scroll ? "Precision" : labels[0], text: Binding(get: { parts[0] }, set: { write($0, linked ? $0 : parts[1], linked) }))
            Button { write(parts[0], parts[1], !linked) } label: { Image(systemName: linked ? "link" : "link.badge.plus") }.help("Link / unlink values")
            TextField(scroll ? "Discrete" : labels[1], text: Binding(get: { parts[1] }, set: { write(linked ? $0 : parts[0], $0, linked) }))
        }
    }
    private func write(_ a: String, _ b: String, _ linked: Bool) { value = linked ? a : scroll ? "precision:\(a),discrete:\(b)" : "\(a),\(b)" }
}
struct ConfigRepeatableEditor: View {
    @ObservedObject var model: ConfigEditorModel
    let key: String
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(model.document.values(key).enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField("Value", text: Binding(get: { let a = model.document.values(key); return a.indices.contains(index) ? a[index] : "" }, set: { text in
                        model.edit { var a = $0.values(key); guard a.indices.contains(index) else { return }; a[index] = text; $0.set(key, a) }
                    }))
                    Button { model.edit { var a = $0.values(key); a.swapAt(index, index - 1); $0.set(key, a) } } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { model.edit { var a = $0.values(key); a.remove(at: index); $0.set(key, a) } } label: { Image(systemName: "minus.circle") }
                }
            }
            Button("Add value", systemImage: "plus") { model.edit { $0.set(key, $0.values(key) + [""]) } }
        }
    }
}

struct ConfigPairCodec {
    static func parse(_ raw: String, scroll: Bool) -> (values: [String], linked: Bool) {
        if scroll && (raw.isEmpty || raw.contains(":")) {
            var values = ["1", "3"]
            for item in raw.components(separatedBy: ",") {
                let pair = item.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pair.count == 2, Double(pair[1]) != nil {
                    if pair[0] == "precision" { values[0] = pair[1] }
                    if pair[0] == "discrete" { values[1] = pair[1] }
                }
            }
            return (values, false)
        }
        let parts = raw.components(separatedBy: ",")
        let first = parts.first ?? "0"
        return ([first, parts.count > 1 ? parts[1] : first], parts.count < 2)
    }
}
