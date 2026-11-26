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
    /// The bundled LICENSE's libraries, in its order.
    public static let bundledLibraries: [String] = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return libraries(in: text)
    }()

    /// Each notice's name: the first line after a `---` or `====` divider,
    /// without its version or remark. Parts of another library ("built
    /// into", "bundled in") and build tools that are not shipped are left
    /// out, as is the footnote.
    static func libraries(in license: String) -> [String] {
        let lines = license.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var names: [String] = []
        for (index, line) in lines.enumerated() where line == "---" || (line.count >= 3 && line.allSatisfy { $0 == "=" }) {
            guard let heading = lines[(index + 1)...].first(where: { !$0.isEmpty }),
                  !heading.hasPrefix("*"),
                  !["built into", "bundled in", "build tool only"].contains(where: heading.contains)
            else { continue }
            var name = heading.components(separatedBy: " (").first ?? heading
            if let last = name.split(separator: " ").last, last.first?.isNumber == true, name.contains(" ") {
                name = String(name.dropLast(last.count + 1))
            }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}
