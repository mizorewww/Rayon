import Foundation

/// A named set of Unicode ranges, as Ghostty writes them (`U+E000-U+F8FF,U+F0000`).
struct CodepointRangeSet: Identifiable, Hashable {
    var id: String { ranges }
    let name: String
    let ranges: String

    static let presets: [CodepointRangeSet] = [
        .init(name: "Nerd Font icons", ranges: "U+E000-U+F8FF,U+F0000-U+FFFFD"),
        .init(name: "Powerline symbols", ranges: "U+E0A0-U+E0D4"),
        .init(name: "Chinese, Japanese and Korean characters", ranges: "U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,U+20000-U+2FA1F"),
        .init(name: "Japanese kana", ranges: "U+3040-U+30FF,U+31F0-U+31FF"),
        .init(name: "Korean Hangul", ranges: "U+1100-U+11FF,U+3130-U+318F,U+AC00-U+D7AF"),
        .init(name: "CJK punctuation and full-width forms", ranges: "U+3000-U+303F,U+FF00-U+FFEF"),
        .init(name: "Emoji", ranges: "U+2600-U+27BF,U+1F300-U+1FAFF"),
        .init(name: "Box drawing and blocks", ranges: "U+2500-U+259F"),
        .init(name: "Braille", ranges: "U+2800-U+28FF"),
        .init(name: "Arrows", ranges: "U+2190-U+21FF"),
        .init(name: "Mathematical operators", ranges: "U+2200-U+22FF"),
        .init(name: "Greek", ranges: "U+0370-U+03FF"),
        .init(name: "Cyrillic", ranges: "U+0400-U+04FF"),
        .init(name: "Hebrew", ranges: "U+0590-U+05FF"),
        .init(name: "Arabic", ranges: "U+0600-U+06FF"),
        .init(name: "Devanagari", ranges: "U+0900-U+097F"),
        .init(name: "Thai", ranges: "U+0E00-U+0E7F"),
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
