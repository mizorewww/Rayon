//
//  LicenseNotices.swift
//  RayonModule
//
//  The libraries the apps ship, read off the bundled LICENSE: the notices
//  `make scan-license` keeps in step with every resolved dependency, so the
//  About pages list what is built in, not a hand-kept list.
//

import Foundation

public enum LicenseNotices {
    /// The platforms a notice's remark can start with, for a library only
    /// one app ships: `CodeEditSourceEditor 0.15.2 (macOS)`.
    enum Platform: String, CaseIterable {
        case macOS
        case iOS

        #if os(macOS)
            static let current = Platform.macOS
        #else
            static let current = Platform.iOS
        #endif
    }

    /// The bundled LICENSE's libraries this app ships, in its order.
    public static let bundledLibraries: [String] = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return libraries(in: text, for: .current)
    }()

    /// Each notice's name: the first line after a `---` or `====` divider,
    /// without its version or remark. Left out: notices whose remark starts
    /// by saying they are part of another library ("built into", "bundled
    /// in") or not shipped ("build tool only"), those for the other
    /// platform, and the footnote.
    static func libraries(in license: String, for platform: Platform) -> [String] {
        let skipped = ["built into", "bundled in", "build tool only"]
            + Platform.allCases.filter { $0 != platform }.map(\.rawValue)
        let lines = license.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var names: [String] = []
        for (index, line) in lines.enumerated() where line == "---" || (line.count >= 3 && line.allSatisfy { $0 == "=" }) {
            guard let heading = lines[(index + 1)...].first(where: { !$0.isEmpty }), !heading.hasPrefix("*") else { continue }
            let parts = heading.components(separatedBy: " (")
            if parts.count > 1, skipped.contains(where: parts[1].hasPrefix) { continue }
            var name = parts[0]
            if let last = name.split(separator: " ").last, last.first?.isNumber == true, name.contains(" ") {
                name = String(name.dropLast(last.count + 1))
            }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}
