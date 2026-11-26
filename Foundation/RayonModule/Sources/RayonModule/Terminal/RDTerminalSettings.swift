//
//  RDTerminalSettings.swift
//  RayonModule
//
//  The terminal settings that iCloud carries: one record holding the keys
//  of config.ghostty that travel (TerminalConfigurationSync says which).
//  The later change wins, as for every record.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDTerminalSettings: StoredRecord {
    public static let tableName = "TerminalSettings"
    /// There is one: every device writes the same record.
    public static let recordID = UUID(uuidString: "7E2A9C4B-1D3F-4E58-9A6B-0C8D2F4E6A10")!

    public var id = RDTerminalSettings.recordID
    /// The keys and their values, as sorted JSON.
    var entries = "{}"

    public var modified = Date()
    public var removed = false
    public var secrets = NoSecrets()

    public init(entries: [String: [String]] = [:]) {
        self.entries = Self.encode(entries)
    }

    public var values: [String: [String]] {
        (try? JSONDecoder().decode([String: [String]].self, from: Data(entries.utf8))) ?? [:]
    }

    static func encode(_ values: [String: [String]]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDTerminalSettings
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
        }

        case id
        case entries
        case modified
        case removed
    }
}
