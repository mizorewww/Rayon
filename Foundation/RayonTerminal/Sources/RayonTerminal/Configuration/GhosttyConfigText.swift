import Foundation

/// The text of a `config.ghostty`, read and changed one key at a time. What a
/// change does not touch (comments, blank lines, other keys and their order)
/// stays exactly as written, so the file remains the user's to edit.
struct GhosttyConfigText: Equatable, Sendable {
    private(set) var lines: [String]

    init(_ text: String = "") {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    var text: String { lines.joined(separator: "\n") }

    /// Every `key = value` line, in order. Comments and blank lines are skipped;
    /// any other line is an error, reported with its line number.
    func entries() throws -> [(key: String, value: String)] {
        try lines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            guard let entry = Self.entry(trimmed) else {
                throw ConfigError("Line \(index + 1): expected key = value")
            }
            return entry
        }
    }

    /// The values set for `key`, in order (a repeatable key such as `keybind`
    /// may have several). Malformed lines are ignored here.
    func values(_ key: String) -> [String] {
        lines.compactMap { line in
            guard let entry = Self.entry(line.trimmingCharacters(in: .whitespaces)), entry.key == key else { return nil }
            return entry.value
        }
    }

    func value(_ key: String) -> String? { values(key).last }

    /// Replaces every line of `key` with one line per value, where the first
    /// such line was, or at the end. No values removes the key.
    mutating func set(_ key: String, _ values: [String]) {
        let replacement = values.map { "\(key) = \($0)" }
        let indices = lines.indices.filter { Self.entry(lines[$0].trimmingCharacters(in: .whitespaces))?.key == key }
        guard let first = indices.first else {
            if !replacement.isEmpty {
                if lines.last?.isEmpty == true { lines.removeLast() }
                lines += replacement + [""]
            }
            return
        }
        for index in indices.reversed() { lines.remove(at: index) }
        lines.insert(contentsOf: replacement, at: first)
    }

    private static func entry(_ line: String) -> (key: String, value: String)? {
        guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
        return (key, value)
    }
}

struct ConfigError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
