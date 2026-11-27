//
//  RDAppSettings.swift
//  RayonModule
//
//  The app settings that iCloud carries: one record holding the values of
//  the settings `AppSettings` declares `.synced`. What belongs to the
//  device, such as the terminal's font size, stays on it. The later change
//  wins, as for every record.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDAppSettings: StoredRecord {
    public static let tableName = "AppSettings"
    /// There is one: every device writes the same record.
    public static let recordID = UUID(uuidString: "3B6F0D2E-8C41-4A97-B5E3-71D9A2C4F058")!

    /// A setting's value, as ConfigurableKit stores it (a JSON value).
    public enum Value: Codable, Equatable, Sendable {
        case bool(Bool)
        case int(Int)
        case string(String)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else {
                self = try .string(container.decode(String.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .bool(value): try container.encode(value)
            case let .int(value): try container.encode(value)
            case let .string(value): try container.encode(value)
            }
        }
    }

    public var id = RDAppSettings.recordID
    /// The keys and their values, as sorted JSON.
    var entries = "{}"

    public var modified = Date()
    public var removed = false
    public var secrets = NoSecrets()

    public init(entries: [String: Value] = [:]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        self.entries = (try? encoder.encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public var values: [String: Value] {
        (try? JSONDecoder().decode([String: Value].self, from: Data(entries.utf8))) ?? [:]
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDAppSettings
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
