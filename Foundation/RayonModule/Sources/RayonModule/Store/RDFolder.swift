//
//  RDFolder.swift
//  RayonModule
//
//  A folder of servers. Servers point at their folder by its id; servers in
//  no folder are in the default one, which has no record. A folder records
//  where its servers come from: made here, or pulled from a UU Remote
//  account.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDFolder: StoredRecord {
    public static let tableName = "Folder"

    public enum Source: Codable, Equatable, Sendable {
        /// Servers are added and removed by hand.
        case local
        /// Servers are the desktop devices of the UU Remote account with this
        /// user id, brought up to date on every refresh.
        case uuRemote(userID: String)
    }

    public var id = UUID()
    public var name = ""
    /// The UU Remote account whose devices the folder holds; nil for a folder
    /// made by hand.
    public var uuRemoteUserID: String?

    public var modified = Date()
    public var removed = false
    public var secrets = NoSecrets()

    public init(id: UUID = UUID(), name: String, source: Source = .local) {
        self.id = id
        self.name = name
        self.source = source
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDFolder
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(name, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
        }

        case id
        case name
        case uuRemoteUserID
        case modified
        case removed
    }

    public var source: Source {
        get { uuRemoteUserID.map { .uuRemote(userID: $0) } ?? .local }
        set {
            switch newValue {
            case .local: uuRemoteUserID = nil
            case let .uuRemote(userID): uuRemoteUserID = userID
            }
        }
    }

    /// Whether its servers come from an account rather than from the user.
    public var isLinked: Bool { uuRemoteUserID != nil }
}
