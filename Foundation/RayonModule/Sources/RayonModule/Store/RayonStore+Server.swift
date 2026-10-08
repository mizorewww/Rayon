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
    func associatedIdentity(for machine: RDMachine) -> RDIdentity? {
        guard let raw = machine.associatedIdentity,
              let uuid = UUID(uuidString: raw)
        else { return nil }
        let identity = identityGroup[uuid]
        return identity.username.isEmpty ? nil : identity
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
