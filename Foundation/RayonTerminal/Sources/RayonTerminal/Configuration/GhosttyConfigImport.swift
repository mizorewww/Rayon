import Foundation

/// Ghostty's config syntax, read into Rayon's settings: the config.ghostty
/// earlier releases kept, the one in a backup made by them, and Ghostty's
/// own for "Import from Ghostty…". Only the options in the catalog, the
/// ones Rayon's terminal uses, are kept.
enum GhosttyConfigImport {
    /// The catalog options `text` sets, each key's values in order, and the
    /// other keys it names.
    static func parse(_ text: String) -> (values: [String: [String]], skipped: [String]) {
        var values: [String: [String]] = [:]
        var skipped: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            guard SettingCatalog.shared.setting(key) != nil else {
                if !skipped.contains(key) { skipped.append(key) }
                continue
            }
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            // An empty value puts the option back to its default.
            if value.isEmpty { values[key] = nil } else { values[key, default: []].append(value) }
        }
        return (values, skipped)
    }
}

struct ConfigError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
