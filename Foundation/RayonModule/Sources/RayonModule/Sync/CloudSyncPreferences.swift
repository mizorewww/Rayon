//
//  CloudSyncPreferences.swift
//  RayonModule
//
//  Whether iCloud sync is on, and what it carries. Folders go with the
//  servers. Known host keys, recent connections and the display settings
//  stay on the device.
//

import Foundation

public struct CloudSyncPreferences: Equatable, Sendable {
    enum Key {
        static let on = "me.mizorewww.rayon.sync.enabled"
        static let servers = "me.mizorewww.rayon.sync.servers"
        static let identities = "me.mizorewww.rayon.sync.identities"
        static let snippets = "me.mizorewww.rayon.sync.snippets"
        static let portForwards = "me.mizorewww.rayon.sync.portForwards"
    }

    public var isOn: Bool
    public var servers: Bool
    public var identities: Bool
    public var snippets: Bool
    public var portForwards: Bool

    public init(isOn: Bool = false, servers: Bool = true, identities: Bool = true, snippets: Bool = true, portForwards: Bool = true) {
        self.isOn = isOn
        self.servers = servers
        self.identities = identities
        self.snippets = snippets
        self.portForwards = portForwards
    }

    public init(defaults: UserDefaults) {
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        self.init(
            isOn: flag(Key.on, false),
            servers: flag(Key.servers, true),
            identities: flag(Key.identities, true),
            snippets: flag(Key.snippets, true),
            portForwards: flag(Key.portForwards, true)
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(isOn, forKey: Key.on)
        defaults.set(servers, forKey: Key.servers)
        defaults.set(identities, forKey: Key.identities)
        defaults.set(snippets, forKey: Key.snippets)
        defaults.set(portForwards, forKey: Key.portForwards)
    }

    /// Whether records of `table` go to iCloud and come from it.
    func syncs(table: String) -> Bool {
        guard isOn else { return false }
        switch table {
        case RDMachine.tableName, RDFolder.tableName: return servers
        case RDIdentity.tableName: return identities
        case RDSnippet.tableName: return snippets
        case RDPortForward.tableName: return portForwards
        default: return false
        }
    }
}
