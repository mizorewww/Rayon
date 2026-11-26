import GhosttyTheme
import SwiftUI

extension TerminalSettings {
    /// The color a color setting gives: its own value, else the theme's,
    /// else Ghostty's default. Values that name another color follow it.
    func effectiveColor(_ key: String, dark: Bool) -> String {
        var value = config.values(key).last ?? ""
        if value.isEmpty, let theme = TerminalThemes.theme(for: self.value("theme"), dark: dark) {
            value = theme.color(key) ?? ""
        }
        if value.isEmpty { value = Self.defaultValues(key).last ?? "" }
        switch value {
        case "cell-foreground": return key == "foreground" ? "#ffffff" : effectiveColor("foreground", dark: dark)
        case "cell-background": return key == "background" ? "#000000" : effectiveColor("background", dark: dark)
        case "":
            switch key {
            case "cursor-color", "selection-background", "bold-color", "search-background", "search-selected-background":
                return effectiveColor("foreground", dark: dark)
            default:
                return effectiveColor("background", dark: dark)
            }
        default: return value
        }
    }

    /// Palette entries set here, by index.
    var paletteOverrides: [Int: String] {
        var result: [Int: String] = [:]
        for item in config.values("palette") {
            let parts = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let index = Int(parts[0]), (0 ... 255).contains(index) { result[index] = parts[1] }
        }
        return result
    }

    func effectivePalette(_ index: Int, dark: Bool) -> String {
        if let color = paletteOverrides[index] { return color }
        if let color = TerminalThemes.theme(for: value("theme"), dark: dark)?.paletteColor(index) { return color }
        let defaults = SettingCatalog.shared.setting("palette")?.defaultValue.values ?? []
        return defaults.indices.contains(index) ? defaults[index] : "#000000"
    }

    /// Sets (or, nil, resets) one palette entry.
    func setPalette(_ index: Int, _ color: String?) {
        var slots = paletteOverrides
        slots[index] = color
        set("palette", slots.keys.sorted().map { "\($0)=\(slots[$0]!)" })
    }
}

/// `theme`: one theme, or one each for light and dark appearance.
struct ThemeEditor: View {
    private var settings: TerminalSettings { .shared }
    @State private var search = ""
    @State private var editingDark = false

    private var value: String { settings.value("theme") }
    private var sides: (light: String, dark: String)? { TerminalThemes.names(value) }
    private var selected: String {
        guard let sides else { return value }
        return editingDark ? sides.dark : sides.light
    }

    private func select(_ name: String) {
        if let sides {
            settings.set("theme", "light:\(editingDark ? sides.light : name),dark:\(editingDark ? name : sides.dark)")
        } else {
            settings.set("theme", name)
        }
    }

    private var themes: [GhosttyThemeDefinition] {
        search.isEmpty ? TerminalThemes.all : TerminalThemes.all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Separate themes for light and dark appearance", isOn: Binding(
                get: { sides != nil },
                set: { settings.set("theme", $0 ? "light:\(value),dark:\(value)" : selected) }
            ))
            if sides != nil {
                Picker("Appearance", selection: $editingDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack {
                Text(selected.isEmpty ? "No theme: the colors below apply." : "Using \(selected)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !selected.isEmpty {
                    Button("No Theme") { select("") }
                }
            }
            if !selected.isEmpty, TerminalThemes.theme(named: selected) == nil {
                Text("“\(selected)” is not a theme Rayon has, so it is not applied.").foregroundStyle(.red).font(.caption)
            }
            TextField("Search \(TerminalThemes.all.count) themes", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(themes) { theme in
                        ThemeSwatch(theme: theme, selected: theme.name == selected) { select(theme.name) }
                    }
                }
                .padding(2)
            }
            .frame(height: 260)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: GhosttyThemeDefinition
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                Text(theme.name).font(.caption.weight(.medium)).lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(0 ..< 8, id: \.self) { index in
                        Rectangle().fill(Color(configHex: theme.paletteColor(index) ?? "#000000")).frame(height: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .foregroundStyle(Color(configHex: theme.color("foreground") ?? "#ffffff"))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(configHex: theme.color("background") ?? "#000000"), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The 16 palette colors, or all 256: each with its color control and reset.
struct PaletteEditor: View {
    private var settings: TerminalSettings { .shared }
    @Environment(\.colorScheme) private var scheme
    @State private var showsAll = false

    var body: some View {
        let overrides = settings.paletteOverrides
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show all 256 colors", isOn: $showsAll)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(0 ..< (showsAll ? 256 : 16), id: \.self) { index in
                    HStack(spacing: 6) {
                        Text("\(index)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                        ColorControl(
                            effective: settings.effectivePalette(index, dark: scheme == .dark),
                            value: overrides[index],
                            title: "Color \(index)"
                        ) { settings.setPalette(index, $0) }
                        Button { settings.setPalette(index, nil) } label: {
                            Label("Reset Color \(index)", systemImage: "arrow.counterclockwise")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(overrides[index] == nil)
                    }
                }
            }
        }
    }
}
