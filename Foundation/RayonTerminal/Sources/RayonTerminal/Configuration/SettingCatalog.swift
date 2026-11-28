import Foundation

/// What Settings knows of every Ghostty option Rayon's terminal uses: its
/// name, documentation, default and the kind of value it takes. libghostty
/// has no API that lists its options, so this is data (`settings.json`, adapted from
/// zerebos/ghostty-config; see NOTICE.txt), and adding an option to it needs
/// no new view.
struct SettingCatalog: Sendable {
    let revision: String
    /// In Ghostty's documentation order.
    let settings: [Setting]
    private let byKey: [String: Setting]

    static let shared: SettingCatalog = {
        struct File: Decodable { let revision: String; let settings: [Setting] }
        guard let url = Bundle.module.url(forResource: "settings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { preconditionFailure("Missing or invalid Ghostty settings catalog") }
        return SettingCatalog(revision: file.revision, settings: file.settings)
    }()

    init(revision: String, settings: [Setting]) {
        self.revision = revision
        self.settings = settings
        byKey = Dictionary(settings.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func setting(_ key: String) -> Setting? { byKey[key] }
}

struct Setting: Decodable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let name: String
    let description: String
    let note: String?
    let platform: [String]?
    let since: String?
    let deprecated: SettingValue?
    let repeatable: Bool?
    let defaultValue: SettingValue
    let widget: Widget?

    enum CodingKeys: String, CodingKey {
        case key, name, description, note, platform, since, deprecated, repeatable, widget
        case defaultValue = "default"
    }

    struct Widget: Decodable, Sendable {
        let type: String
        let min: Double?
        let max: Double?
        let step: Double?
        let placeholder: String?
        let allowEmpty: Bool?
        let options: [Option]?
        let presets: [Option]?
        let features: [Feature]?
        let labels: [String]?
    }

    struct Option: Decodable, Identifiable, Hashable, Sendable {
        var id: String { value }
        let value: String
        let name: String

        init(value: String, name: String) {
            self.value = value
            self.name = name
        }

        enum CodingKeys: String, CodingKey { case value, name, label }
        init(from decoder: any Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                value = text
                name = text
            } else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try c.decode(String.self, forKey: .value)
                name = try c.decodeIfPresent(String.self, forKey: .name)
                    ?? c.decodeIfPresent(String.self, forKey: .label) ?? value
            }
        }
    }

    struct Feature: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let defaultValue: Bool
        enum CodingKeys: String, CodingKey { case id, label; case defaultValue = "default" }
    }

    /// The documentation without markup, for help text and search.
    var plainDescription: String {
        description
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
    }

    /// The first sentence of the documentation.
    var summary: String {
        let plain = plainDescription
        let firstLine = plain.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? plain
        if let range = firstLine.range(of: ". ") { return String(firstLine[..<range.lowerBound]) + "." }
        return firstLine
    }

    static func documentationURL(_ key: String) -> URL {
        URL(string: "https://ghostty.org/docs/config/reference#" + key)!
    }
}

enum SettingValue: Decodable, Equatable, Sendable {
    case scalar(String), list([String])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let a = try? c.decode([String].self) { self = .list(a) }
        else if let b = try? c.decode(Bool.self) { self = .scalar(String(b)) }
        else { self = .scalar(try c.decode(String.self)) }
    }

    var values: [String] {
        switch self {
        case let .scalar(s): s.isEmpty ? [] : [s]
        case let .list(a): a
        }
    }
}
