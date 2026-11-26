//
//  RDMachine+ConnectionCheck.swift
//  RayonModule
//
//  "Add and Connect": before a new server is saved, connect to it and find
//  an identity that signs in. Shared by the macOS and iOS server editors.
//

import Foundation
import RayonSSH

public enum ServerConnectionCheck {
    public enum Outcome: Sendable {
        /// Signed in with this identity; the banner the server sent.
        case authenticated(identity: RDIdentity.ID, banner: String)
        /// The server could not be reached; why, when known.
        case unreachable(reason: String?)
        /// Reached, but no identity tried could sign in.
        case rejected
    }

    /// Connects to `draft` and signs in with `identity`, or else with each
    /// identity that authenticates automatically.
    public static func run(
        _ draft: RDMachine,
        identity chosen: RDIdentity?,
        candidates: [RDIdentity],
        timeout: NSNumber
    ) async -> Outcome {
        do {
            let (connection, identity) = try await draft.connectSSH(
                identity: chosen,
                autoIdentities: candidates,
                timeout: .seconds(max(5, timeout.intValue))
            )
            let banner = connection.serverVersion
            await connection.close()
            return .authenticated(identity: identity.id, banner: banner)
        } catch let failure as RDMachine.SSHFailure {
            return failure.unreachable ? .unreachable(reason: failure.message) : .rejected
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }
    }
}
