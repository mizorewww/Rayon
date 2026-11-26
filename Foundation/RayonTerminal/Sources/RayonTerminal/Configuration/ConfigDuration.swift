import Foundation
import RayonDesign
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
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: RX.Space.s2) {
                TextField("e.g. 1h30m", text: $value)
                    .textFieldStyle(.rxMono)
                    .frame(width: 140)
                Menu {
                    ForEach(ConfigDuration.units, id: \.self) { unit in
                        Button("Add 1 \(ConfigDuration.names[unit] ?? unit)") { add(1, unit) }
                    }
                    if allowEmpty {
                        Divider()
                        Button("Unset") { value = "" }
                    }
                } label: {
                    Label("Units", systemImage: "clock")
                }
                .rxButtonMenu(indicator: false)
                .buttonStyle(.rx(iconOnly: true))
                .fixedSize()
                .help("Add a unit")
            }
            switch Result(catching: { try ConfigDuration.parse(value, allowEmpty: allowEmpty) }) {
            case let .success(segments):
                if !segments.isEmpty { HelpText(ConfigDuration.humanize(segments)) }
            case let .failure(error):
                HelpText(error.localizedDescription, isError: true)
            }
        }
    }

    private func add(_ number: Int, _ unit: String) {
        var segments = (try? ConfigDuration.parse(value, allowEmpty: true)) ?? []
        if let index = segments.firstIndex(where: { $0.1 == unit }) {
            segments[index].0 += number
        } else {
            segments.append((number, unit))
        }
        value = segments.map { "\($0.0)\($0.1)" }.joined()
    }
}
