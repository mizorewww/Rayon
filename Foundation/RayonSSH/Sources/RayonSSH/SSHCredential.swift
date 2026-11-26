//
//  SSHCredential.swift
//  RayonSSH
//

import Foundation
import NIOCore
@preconcurrency import NIOSSH

/// One way to sign in.
public enum SSHCredential: Sendable {
    case password(String)
    case privateKey(SSHPrivateKey)
    /// Each key the agent holds.
    case agent(SSHAgent)
}

extension SSHCredential {
    /// What signing in with this credential offers the server, in order:
    /// an RSA key offers SHA-512, then SHA-256, then SHA-1 signatures.
    func offers() throws -> [NIOSSHUserAuthenticationOffer.Offer] {
        switch self {
        case let .password(password):
            return [.password(.init(password: password))]
        case let .privateKey(key):
            return try key.offers().map { .privateKey(.init(privateKey: $0)) }
        case let .agent(agent):
            return try agent.offers().map { .privateKey(.init(privateKey: $0)) }
        }
    }
}

/// Makes one offer, when the server takes that kind, and gives up after it.
final class SSHCredentialAuthenticator: NIOSSHClientUserAuthenticationDelegate, Sendable {
    private let username: String
    private let offer: NIOSSHUserAuthenticationOffer.Offer

    init(username: String, offer: NIOSSHUserAuthenticationOffer.Offer) {
        self.username = username
        self.offer = offer
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        let usable = switch offer {
        case .password: availableMethods.contains(.password)
        case .privateKey: availableMethods.contains(.publicKey)
        default: false
        }
        guard usable else {
            nextChallengePromise.fail(SSHError.authenticationFailed)
            return
        }
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: offer))
    }
}
