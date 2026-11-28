import GhosttyTheme
import SwiftUI

extension TerminalSettings {
    /// The color a color setting gives: its own value, else the theme's,
    /// else Ghostty's default. Values that name another color follow it.
    func effectiveColor(_ key: String, dark: Bool) -> String {
        var value = config[key, default: []].last ?? ""
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
        for item in config["palette", default: []] {
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

/// `theme`: one theme, or one each for light and dark appearance. Each is a
/// button showing the theme that opens the gallery, so the page does not
/// hold a scrolling grid of hundreds of themes inside its own scrolling.
struct ThemeEditor: View {
    private var settings: TerminalSettings { .shared }

    private var value: String { settings.value("theme") }
    private var sides: (light: String, dark: String)? { TerminalThemes.names(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(.init("Separate themes for light and dark appearance", bundle: .module), isOn: Binding(
                get: { sides != nil },
                set: { separate in
                    if separate {
                        settings.set("theme", "light:\(value),dark:\(value)")
                    } else {
                        settings.set("theme", sides?.light ?? value)
                    }
                }
            ))
            if let sides {
                ThemeChoice(title: String(localized: "Light", bundle: .module), name: sides.light) {
                    settings.set("theme", "light:\($0),dark:\(sides.dark)")
                }
                ThemeChoice(title: String(localized: "Dark", bundle: .module), name: sides.dark) {
                    settings.set("theme", "light:\(sides.light),dark:\($0)")
                }
            } else {
                ThemeChoice(title: nil, name: value) { settings.set("theme", $0) }
            }
        }
    }
}

/// One theme: the button that shows it and opens the gallery.
private struct ThemeChoice: View {
    let title: String?
    let name: String
    let select: (String) -> Void
    @State private var showsGallery = false

    var body: some View {
        HStack {
            if let title {
                Text(title)
            }
            Spacer()
            Button { showsGallery = true } label: {
                HStack(spacing: 8) {
                    if let theme = TerminalThemes.theme(named: name) {
                        ThemeStrip(theme: theme)
                            .frame(width: 64, height: 10)
                    }
                    Text(name.isEmpty ? String(localized: "No Theme", bundle: .module) : name)
                }
            }
            .popover(isPresented: $showsGallery) {
                ThemeGallery(selected: name, select: select)
            }
        }
        if !name.isEmpty, TerminalThemes.theme(named: name) == nil {
            Text("“\(name)” is not a theme Rayon has, so it is not applied.", bundle: .module).foregroundStyle(.red).font(.caption)
        }
    }
}

/// Every theme, searchable; picking one applies it at once, so the preview
/// behind shows it while the gallery stays open.
private struct ThemeGallery: View {
    let selected: String
    let select: (String) -> Void
    @State private var search = ""

    private var themes: [GhosttyThemeDefinition] {
        search.isEmpty ? TerminalThemes.all : TerminalThemes.all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(String(localized: "Search themes", bundle: .module), text: $search,
                          prompt: Text("Search \(TerminalThemes.all.count) themes", bundle: .module))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Button(.init("No Theme", bundle: .module)) { select("") }
                    .disabled(selected.isEmpty)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(themes) { theme in
                        ThemeSwatch(theme: theme, selected: theme.name == selected) { select(theme.name) }
                    }
                }
                .padding(2)
            }
            if themes.isEmpty {
                Text("No theme matches.", bundle: .module).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 320, idealWidth: 500, minHeight: 360, idealHeight: 460)
    }
}

/// A theme's first eight palette colors in a row.
private struct ThemeStrip: View {
    let theme: GhosttyThemeDefinition

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 8, id: \.self) { index in
                Rectangle().fill(Color(configHex: theme.paletteColor(index) ?? "#000000"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
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
                ThemeStrip(theme: theme)
                    .frame(height: 8)
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
            Toggle(.init("Show all 256 colors", bundle: .module), isOn: $showsAll)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(0 ..< (showsAll ? 256 : 16), id: \.self) { index in
                    HStack(spacing: 6) {
                        Text("\(index)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                        ColorControl(
                            effective: settings.effectivePalette(index, dark: scheme == .dark),
                            value: overrides[index],
                            title: String(localized: "Color \(index)", bundle: .module)
                        ) { settings.setPalette(index, $0) }
                        Button { settings.setPalette(index, nil) } label: {
                            Label(.init("Reset Color \(index)", bundle: .module), systemImage: "arrow.counterclockwise")
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
