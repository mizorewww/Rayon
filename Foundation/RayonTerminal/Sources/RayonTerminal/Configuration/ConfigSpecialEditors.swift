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
            RXSearchField("Search \(ConfigCatalog.shared.themeNames.count) themes", text: $search, width: nil)
            HStack(spacing: RX.Space.s2) {
                Text(selected.isEmpty ? "No theme: the base colors below apply." : "Using \(selected)")
                    .font(.rxHelp)
                    .foregroundStyle(.rxInkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: RX.Space.s2)
                if !selected.isEmpty {
                    Button("Remove") { value = "" }
                        .buttonStyle(.rx(.plain, size: .small))
                        .fixedSize()
                        .help("Use no theme; the base colors below apply")
                }
            }
            if !selected.isEmpty && ConfigCatalog.shared.themes[selected] == nil {
                HelpText("“\(selected)” is not a bundled theme, so it is not applied. Pick one below.", isError: true)
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
