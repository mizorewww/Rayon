import Foundation

/// Upstream metadata is kept as data, so adding a setting does not require another view.
struct ConfigCatalog: Decodable, Sendable {
    let revision: String
    let registry: [String: ConfigSetting]
    let navigation: [ConfigPanel]
    let themes: [String: ConfigTheme]

    // Derived once at decode time: views read these on every render.
    let settings: [ConfigSetting]
    /// Settings that take effect in Rayon's terminal. Everything else in the
    /// upstream catalog (windows, tabs, GTK, Linux, app icons, quick terminal…)
    /// belongs to standalone Ghostty and is not shown. Settings arranges these
    /// with `ConfigLayout`, not the upstream navigation.
    let rayonSettings: [ConfigSetting]
    let themeNames: [String]
    private let byKey: [String: ConfigSetting]

    static let shared: ConfigCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ConfigCatalog.self, from: data)
        else { preconditionFailure("Missing or invalid Ghostty configuration catalog") }
        return catalog
    }()

    static let rayonKeys: Set<String> = RayonTerminalConfiguration.supportedKeys.subtracting(ConfigLayout.hiddenKeys)

    private enum CodingKeys: String, CodingKey { case revision, registry, navigation, themes }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(String.self, forKey: .revision)
        registry = try c.decode([String: ConfigSetting].self, forKey: .registry)
        navigation = try c.decode([ConfigPanel].self, forKey: .navigation)
        themes = try c.decode([String: ConfigTheme].self, forKey: .themes)

        settings = registry.values.sorted { $0.key < $1.key }
        rayonSettings = settings.filter { Self.rayonKeys.contains($0.key) }
        byKey = Dictionary(settings.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        themeNames = themes.keys.sorted()
    }

    func setting(key: String) -> ConfigSetting? { byKey[key] }
}

struct ConfigSetting: Decodable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let name: String
    let description: String
    let note: String?
    let platform: [String]?
    let since: String?
    let disabled: Bool?
    let deprecated: ConfigValue?
    let repeatable: Bool?
    let defaultValue: ConfigValue
    let widget: ConfigWidget?
    enum CodingKeys: String, CodingKey {
        case key, name, description, note, platform, since, disabled, deprecated, repeatable, widget
        case defaultValue = "default"
    }
}

enum ConfigValue: Decodable, Equatable, Sendable {
    case scalar(String), list([String])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let a = try? c.decode([String].self) { self = .list(a) }
        else if let b = try? c.decode(Bool.self) { self = .scalar(String(b)) }
        else { self = .scalar(try c.decode(String.self)) }
    }
    var values: [String] { switch self { case let .scalar(s): [s]; case let .list(a): a } }
    var text: String { values.joined(separator: "\n") }
}

struct ConfigWidget: Decodable, Sendable {
    let type: String
    let min: Double?
    let max: Double?
    let step: Double?
    let integer: Bool?
    let placeholder: String?
    let allowEmpty: Bool?
    let options: [ConfigOption]?
    let presets: [ConfigOption]?
    let features: [ConfigFeature]?
    let labels: [String]?
}
struct ConfigOption: Decodable, Identifiable, Sendable {
    var id: String { value }
    let value: String
    let name: String
    let description: String?
    let disabled: Bool?
    enum CodingKeys: String, CodingKey { case value, name, label, description, disabled }
    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            value = text; name = text; description = nil; disabled = nil
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decode(String.self, forKey: .value)
            name = try c.decodeIfPresent(String.self, forKey: .name)
                ?? c.decodeIfPresent(String.self, forKey: .label) ?? value
            description = try c.decodeIfPresent(String.self, forKey: .description)
            disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled)
        }
    }
}
struct ConfigFeature: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let description: String?
    let defaultValue: Bool
    enum CodingKeys: String, CodingKey { case id, label, description; case defaultValue = "default" }
}
struct ConfigPanel: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let note: String?
    let groups: [ConfigGroup]?
    let pages: [ConfigPanel]?
    var settingIDs: [String] {
        (groups ?? []).flatMap(\.settings) + (pages ?? []).flatMap(\.settingIDs)
    }
}
struct ConfigGroup: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let note: String?
    let preview: String?
    let settings: [String]
}
struct ConfigTheme: Decodable, Sendable {
    let palette: [String]
    let background: String?
    let foreground: String?
    let cursorColor: String?
    let cursorText: String?
    let selectionBackground: String?
    let selectionForeground: String?
    var entries: [(String, String)] {
        [("background", background), ("foreground", foreground), ("cursor-color", cursorColor),
         ("cursor-text", cursorText), ("selection-background", selectionBackground),
         ("selection-foreground", selectionForeground)].compactMap { k, v in v.map { (k, $0) } }
        + palette.enumerated().map { ("palette", "\($0.offset)=\($0.element)") }
    }
}
