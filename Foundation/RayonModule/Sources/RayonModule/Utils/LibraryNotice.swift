//
//  LibraryNotice.swift
//  RayonModule
//
//  A library the app ships and its license, from the bundled Libraries.json
//  that `make sync-libraries` writes from LICENSE and `make scan-license`
//  keeps in step with every pinned dependency.
//

import Foundation

public struct LibraryNotice: Decodable, Identifiable, Hashable, Sendable {
    public let name: String
    public let version: String?
    public let url: URL?
    /// `owner/repo` for GitHub, the address otherwise.
    public let repository: String?
    /// Its SPDX identifiers, e.g. "MIT" or "BSD-3-Clause, MIT"; nil when the
    /// project carries no license file.
    public let license: String?
    let platforms: [String]
    public let text: String

    public var id: String {
        name
    }

    #if os(macOS)
        static let platform = "macOS"
    #else
        static let platform = "iOS"
    #endif

    /// What this app ships, Rayon included, by name.
    public static let bundled: [LibraryNotice] = {
        guard let url = Bundle.main.url(forResource: "Libraries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let libraries = try? shipped(in: data, on: platform)
        else { return [] }
        return libraries
    }()

    static func shipped(in data: Data, on platform: String) throws -> [LibraryNotice] {
        try JSONDecoder().decode([LibraryNotice].self, from: data)
            .filter { $0.platforms.contains(platform) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
