//
//  CloudSyncPreferences.swift
//  RayonModule
//
//  Whether iCloud sync is on, and what it carries. Folders go with the
//  servers. Known host keys, recent connections and what belongs to the
//  device stay on it, as do the terminal's font size and padding.
//

import Foundation

public struct CloudSyncPreferences: Equatable, Sendable {
    public var isOn: Bool
    public var servers: Bool
    public var identities: Bool
    public var snippets: Bool
    public var portForwards: Bool
    public var terminalSettings: Bool
    public var appSettings: Bool

    public init(
        isOn: Bool = false,
        servers: Bool = true,
        identities: Bool = true,
        snippets: Bool = true,
        portForwards: Bool = true,
        terminalSettings: Bool = true,
        appSettings: Bool = true
    ) {
        self.isOn = isOn
        self.servers = servers
        self.identities = identities
        self.snippets = snippets
        self.portForwards = portForwards
        self.terminalSettings = terminalSettings
        self.appSettings = appSettings
    }

    /// The choices as this device keeps them.
    public static var stored: CloudSyncPreferences {
        CloudSyncPreferences(
            isOn: AppSettings.syncEnabled.value,
            servers: AppSettings.syncsServers.value,
            identities: AppSettings.syncsIdentities.value,
            snippets: AppSettings.syncsSnippets.value,
            portForwards: AppSettings.syncsPortForwards.value,
            terminalSettings: AppSettings.syncsTerminalSettings.value,
            appSettings: AppSettings.syncsAppSettings.value
        )
    }

    public func store() {
        AppSettings.syncEnabled.set(isOn)
        AppSettings.syncsServers.set(servers)
        AppSettings.syncsIdentities.set(identities)
        AppSettings.syncsSnippets.set(snippets)
        AppSettings.syncsPortForwards.set(portForwards)
        AppSettings.syncsTerminalSettings.set(terminalSettings)
        AppSettings.syncsAppSettings.set(appSettings)
    }

    /// The tables whose records go to iCloud and come from it.
    var syncedTables: Set<String> {
        Set(RayonStorage.recordTypes.map { $0.tableName }.filter { syncs(table: $0) })
    }

    /// Whether records of `table` go to iCloud and come from it.
    func syncs(table: String) -> Bool {
        guard isOn else { return false }
        switch table {
        case RDMachine.tableName, RDFolder.tableName: return servers
        case RDIdentity.tableName: return identities
        case RDSnippet.tableName: return snippets
        case RDPortForward.tableName: return portForwards
        case RDTerminalSettings.tableName: return terminalSettings
        case RDAppSettings.tableName: return appSettings
        default: return false
        }
    }
}
