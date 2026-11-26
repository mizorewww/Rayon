import Foundation
import GhosttyTheme

/// Every theme `theme = …` can name: the themes Rayon offered before that
/// libghostty-spm's `GhosttyThemeCatalog` lacks or defines otherwise
/// (`themes.json`), so no theme someone picked goes away or looks different,
/// then the rest of the catalog.
enum TerminalThemes {
    static let all: [GhosttyThemeDefinition] = {
        let kept = Set(supplement.map(\.name))
        return (supplement + GhosttyThemeCatalog.allThemes.filter { !kept.contains($0.name) })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    private static let byName: [String: GhosttyThemeDefinition] =
        Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    static func theme(named name: String) -> GhosttyThemeDefinition? { byName[name] }

    private static let supplement: [GhosttyThemeDefinition] = {
        struct Entry: Decodable {
            let name: String
            let background: String
            let foreground: String
            let cursorColor: String?
            let cursorText: String?
            let selectionBackground: String?
            let selectionForeground: String?
            let palette: [String]
        }
        guard let url = Bundle.module.url(forResource: "themes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        // GhosttyTheme writes colors without "#".
        func hex(_ color: String) -> String { color.hasPrefix("#") ? String(color.dropFirst()) : color }
        return entries.map { entry in
            GhosttyThemeDefinition(
                name: entry.name,
                background: hex(entry.background),
                foreground: hex(entry.foreground),
                cursorColor: entry.cursorColor.map(hex),
                cursorText: entry.cursorText.map(hex),
                selectionBackground: entry.selectionBackground.map(hex),
                selectionForeground: entry.selectionForeground.map(hex),
                palette: Dictionary(uniqueKeysWithValues: entry.palette.enumerated().map { ($0.offset, hex($0.element)) })
            )
        }
    }()

    /// `theme = A` names one theme for both appearances; `light:A,dark:B` one each.
    static func names(_ value: String) -> (light: String, dark: String)? {
        guard value.contains("light:") || value.contains("dark:") else { return nil }
        let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        func side(_ prefix: String) -> String {
            parts.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } ?? ""
        }
        return (side("light:"), side("dark:"))
    }

    /// The theme a `theme` value gives one appearance.
    static func theme(for value: String, dark: Bool) -> GhosttyThemeDefinition? {
        let name = names(value).map { dark ? $0.dark : $0.light } ?? value
        return theme(named: name)
    }
}

extension GhosttyThemeDefinition {
    /// A theme color as a config value, with "#".
    func color(_ key: String) -> String? {
        let raw: String? = switch key {
        case "background": background
        case "foreground": foreground
        case "cursor-color": cursorColor
        case "cursor-text": cursorText
        case "selection-background": selectionBackground
        case "selection-foreground": selectionForeground
        default: nil
        }
        return raw.map { $0.hasPrefix("#") ? $0 : "#" + $0 }
    }

    func paletteColor(_ index: Int) -> String? {
        palette[index].map { $0.hasPrefix("#") ? $0 : "#" + $0 }
    }
}
