import Foundation

/// How compound values are read and written: a pair of numbers, scroll
/// speeds, durations and lengths.
enum PairValue {
    /// `a,b` or one value for both; scroll speeds are `precision:a,discrete:b`.
    static func parse(_ raw: String, scroll: Bool, fallback: [String] = ["1", "3"]) -> (values: [String], linked: Bool) {
        if scroll && (raw.isEmpty || raw.contains(":")) {
            var values = fallback
            for item in raw.components(separatedBy: ",") {
                let pair = item.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pair.count == 2, Double(pair[1]) != nil {
                    if pair[0] == "precision" { values[0] = pair[1] }
                    if pair[0] == "discrete" { values[1] = pair[1] }
                }
            }
            return (values, false)
        }
        let parts = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let first = parts.first ?? "0"
        return ([first, parts.count > 1 ? parts[1] : first], parts.count < 2)
    }

    static func render(_ a: String, _ b: String, linked: Bool, scroll: Bool) -> String {
        if scroll { return "precision:\(a),discrete:\(b)" }
        return linked ? a : "\(a),\(b)"
    }
}

/// Ghostty's durations: `1h30m`, `250ms`.
enum DurationValue {
    static let units = ["ns", "us", "ms", "s", "m", "h", "d", "y"]
    static let names = ["ns": "nanosecond", "us": "microsecond", "ms": "millisecond", "s": "second", "m": "minute", "h": "hour", "d": "day", "y": "year"]

    static func parse(_ source: String, allowEmpty: Bool) throws -> [(Int, String)] {
        var remaining = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.isEmpty {
            if allowEmpty { return [] }
            throw ConfigError("A duration is required")
        }
        var result: [(Int, String)] = []
        var seen: Set<String> = []
        while !remaining.isEmpty {
            remaining = remaining.trimmingCharacters(in: .whitespaces)
            if remaining.isEmpty { break }
            let digits = remaining.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { throw ConfigError("Expected a whole number") }
            remaining.removeFirst(digits.count)
            // The longest unit first: "ms" before "m".
            guard let unit = units.sorted(by: { $0.count > $1.count }).first(where: { remaining.hasPrefix($0) }) else {
                throw ConfigError("Missing or unknown unit (ns, us, ms, s, m, h, d, y)")
            }
            guard seen.insert(unit).inserted else { throw ConfigError("\(unit) appears twice") }
            remaining.removeFirst(unit.count)
            result.append((number, unit))
        }
        return result
    }

    static func describe(_ segments: [(Int, String)]) -> String {
        segments.map { "\($0.0) \(names[$0.1] ?? $0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: ", ")
    }
}

/// A metric adjustment: points, or a percentage of the default (`20%`).
enum LengthValue {
    static func parse(_ raw: String) -> (number: String, percent: Bool) {
        raw.hasSuffix("%") ? (String(raw.dropLast()), true) : (raw, false)
    }

    static func render(_ number: String, percent: Bool) -> String {
        number.isEmpty ? "" : number + (percent ? "%" : "")
    }
}

extension Double {
    /// As a config value: no exponent, no grouping, a "." separator whatever
    /// the region, and no trailing zeros.
    var configText: String {
        formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0 ... 4)))
    }
}
