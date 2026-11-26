//
//  RayonStore+Server.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/1.
//

import Foundation
import NSRemoteShell

public extension RayonStore {
    /// The identity referenced by `machine.associatedIdentity`; nil when the
    /// reference is unset, malformed, or resolves to a placeholder.
    /// Main thread; worker queues read `workerAssociatedIdentity(for:)`.
    func associatedIdentity(for machine: RDMachine) -> RDIdentity? {
        guard let raw = machine.associatedIdentity,
              let uuid = UUID(uuidString: raw)
        else { return nil }
        let identity = identityGroup[uuid]
        return identity.username.isEmpty ? nil : identity
    }

    /// The saved server an alias names, as `ssh myserver` names a Host in
    /// ~/.ssh/config: the first whose name matches, ignoring case, else the
    /// first whose address does. Nil when none does.
    func machine(matchingAlias alias: String) -> RDMachine? {
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return nil }
        let saved = machineGroup.machines.filter { $0.isNotPlaceholder() }
        func matches(_ value: String) -> Bool {
            value.caseInsensitiveCompare(alias) == .orderedSame
        }
        return saved.first { matches($0.name) } ?? saved.first { matches($0.remoteAddress) }
    }

    /// The saved server Quick Connect input names: `myserver` or
    /// `ssh myserver`. Nil when the input is not a lone alias or no saved
    /// server matches it.
    func machine(matchingQuickConnect input: String) -> RDMachine? {
        SSHCommandReader.quickConnectAlias(input).flatMap { machine(matchingAlias: $0) }
    }

    @discardableResult
    func registerServer(
        withAddress: String,
        withPort: String,
        withIdentity: RDIdentity.ID,
        session: NSRemoteShell
    ) -> RDMachine {
        let machine = RDMachine(
            remoteAddress: withAddress,
            remotePort: withPort,
            name: withAddress,
            group: "",
            lastConnection: Date(),
            lastBanner: session.remoteBanner ?? "",
            comment: session.resolvedRemoteIpAddress ?? "",
            associatedIdentity: withIdentity.uuidString,
            attachment: [:]
        )
        machineGroup.insert(machine)
        return machine
    }
}
