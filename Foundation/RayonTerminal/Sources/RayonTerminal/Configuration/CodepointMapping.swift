import Foundation

/// A named set of Unicode ranges, as Ghostty writes them (`U+E000-U+F8FF,U+F0000`).
struct CodepointRangeSet: Identifiable, Hashable {
    var id: String { ranges }
    let name: String
    let ranges: String

    static let presets: [CodepointRangeSet] = [
        .init(name: String(localized: "Nerd Font icons", bundle: .module), ranges: "U+E000-U+F8FF,U+F0000-U+FFFFD"),
        .init(name: String(localized: "Powerline symbols", bundle: .module), ranges: "U+E0A0-U+E0D4"),
        .init(name: String(localized: "Chinese, Japanese and Korean characters", bundle: .module), ranges: "U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,U+20000-U+2FA1F"),
        .init(name: String(localized: "Japanese kana", bundle: .module), ranges: "U+3040-U+30FF,U+31F0-U+31FF"),
        .init(name: String(localized: "Korean Hangul", bundle: .module), ranges: "U+1100-U+11FF,U+3130-U+318F,U+AC00-U+D7AF"),
        .init(name: String(localized: "CJK punctuation and full-width forms", bundle: .module), ranges: "U+3000-U+303F,U+FF00-U+FFEF"),
        .init(name: String(localized: "Emoji", bundle: .module), ranges: "U+2600-U+27BF,U+1F300-U+1FAFF"),
        .init(name: String(localized: "Box drawing and blocks", bundle: .module), ranges: "U+2500-U+259F"),
        .init(name: String(localized: "Braille", bundle: .module), ranges: "U+2800-U+28FF"),
        .init(name: String(localized: "Arrows", bundle: .module), ranges: "U+2190-U+21FF"),
        .init(name: String(localized: "Mathematical operators", bundle: .module), ranges: "U+2200-U+22FF"),
        .init(name: String(localized: "Greek", bundle: .module), ranges: "U+0370-U+03FF"),
        .init(name: String(localized: "Cyrillic", bundle: .module), ranges: "U+0400-U+04FF"),
        .init(name: String(localized: "Hebrew", bundle: .module), ranges: "U+0590-U+05FF"),
        .init(name: String(localized: "Arabic", bundle: .module), ranges: "U+0600-U+06FF"),
        .init(name: String(localized: "Devanagari", bundle: .module), ranges: "U+0900-U+097F"),
        .init(name: String(localized: "Thai", bundle: .module), ranges: "U+0E00-U+0E7F"),
    ]

    /// A preset's name, or the ranges themselves for a custom set.
    static func describe(_ ranges: String) -> String {
        presets.first { $0.ranges.caseInsensitiveCompare(ranges) == .orderedSame }?.name ?? ranges
    }
}

/// One `font-codepoint-map` entry: `ranges=Family`.
struct CodepointMapping: Equatable {
    var ranges: String
    var family: String

    init(ranges: String, family: String) {
        self.ranges = ranges
        self.family = family
    }

    init?(_ entry: String) {
        guard let eq = entry.lastIndex(of: "=") else { return nil }
        ranges = entry[..<eq].trimmingCharacters(in: .whitespaces)
        family = entry[entry.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    }

    var rendered: String { "\(ranges)=\(family)" }
}
