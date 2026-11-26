//
//  RDSnippet.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/10.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDSnippet: StoredRecord {
    public static let tableName = "Snippet"
    public static let defaultSymbol = "terminal"

    public var id = UUID()

    public var name = ""
    public var group = ""
    public var code = ""
    public var comment = ""
    /// The SF Symbol shown for it; empty for the default.
    public var symbol = ""

    public var modified = Date()
    public var removed = false
    public var secrets = NoSecrets()

    public init(
        id: UUID = UUID(),
        name: String = "",
        group: String = "",
        code: String = "",
        comment: String = "",
        symbol: String = ""
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.code = code
        self.comment = comment
        self.symbol = symbol
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDSnippet
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
        }

        case id
        case name
        // "group" is an SQL keyword.
        case group = "groupName"
        case code
        case comment
        case symbol
        case modified
        case removed
    }

    /// The symbol to draw: its own, else the default.
    public var displaySymbol: String {
        symbol.isEmpty ? Self.defaultSymbol : symbol
    }

    public func isQualifiedForSearch(text: String) -> Bool {
        let searchText = text.lowercased()
        return [name, group, code, comment].contains { $0.lowercased().contains(searchText) }
    }
}
