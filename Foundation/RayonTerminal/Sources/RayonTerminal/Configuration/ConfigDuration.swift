import Foundation
import SwiftUI

struct ConfigDuration {
    static let units = ["ns", "us", "ms", "s", "m", "h", "d", "y"]
    static let names = ["ns": "nanosecond", "us": "microsecond", "ms": "millisecond", "s": "second", "m": "minute", "h": "hour", "d": "day", "y": "year"]
    static func parse(_ source: String, allowEmpty: Bool) throws -> [(Int, String)] {
        var remaining = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.isEmpty {
            if allowEmpty { return [] }; throw ConfigError.message("Value is required")
        }
        var result: [(Int, String)] = []; var seen: Set<String> = []
        while !remaining.isEmpty {
            remaining = remaining.trimmingCharacters(in: .whitespaces)
            if remaining.isEmpty { break }
            let digits = remaining.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { throw ConfigError.message("Expected a non-negative integer") }
            remaining.removeFirst(digits.count)
            guard let unit = units.first(where: { remaining.hasPrefix($0) }) else { throw ConfigError.message("Missing or unknown duration unit") }
            guard seen.insert(unit).inserted else { throw ConfigError.message("Duplicate unit: \(unit)") }
            remaining.removeFirst(unit.count); result.append((number, unit))
        }
        return result
    }
    static func humanize(_ segments: [(Int, String)]) -> String {
        segments.map { "\($0.0) \(names[$0.1] ?? $0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: ", ")
    }
}
struct ConfigDurationInput: View {
    @Binding var value: String
    let allowEmpty: Bool
    @State private var amount = "1"
    @State private var unit = "s"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. 1h30m", text: $value)
            HStack {
                TextField("Amount", text: $amount).frame(width: 80)
                Picker("Unit", selection: $unit) { ForEach(ConfigDuration.units, id: \.self) { Text(ConfigDuration.names[$0] ?? $0).tag($0) } }.labelsHidden().frame(width: 140)
                Button("Set component") {
                    guard let number = Int(amount), number >= 0 else { return }
                    var segments = (try? ConfigDuration.parse(value, allowEmpty: true)) ?? []
                    segments.removeAll { $0.1 == unit }; segments.append((number, unit))
                    value = segments.map { "\($0.0)\($0.1)" }.joined()
                }
                if allowEmpty { Button("Unset") { value = "" } }
            }
            switch Result(catching: { try ConfigDuration.parse(value, allowEmpty: allowEmpty) }) {
            case let .success(segments): Text(segments.isEmpty ? "Default / Unset" : ConfigDuration.humanize(segments)).font(.caption).foregroundStyle(.secondary)
            case let .failure(error): Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
