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

/// One password or key offered to the server, each attempt on a
/// connection of its own.
struct SignInOffer: Sendable {
    let offer: NIOSSHUserAuthenticationOffer.Offer
    /// The same RSA key signing with SHA-256, then SHA-1, for a server
    /// that may not take the SHA-512 signature `offer` makes.
    var fallbacks: [NIOSSHUserAuthenticationOffer.Offer] = []
    /// The agent signs: it may wait for the person first.
    var usesAgent = false

    /// `keys` are one key's signature algorithms, most preferred first.
    init?(_ keys: [NIOSSHPrivateKey]) {
        guard let first = keys.first else { return nil }
        offer = .privateKey(.init(privateKey: first))
        fallbacks = keys.dropFirst().map { .privateKey(.init(privateKey: $0)) }
    }

    init(password: String) {
        offer = .password(.init(password: password))
    }
}

extension SSHCredential {
    /// What signing in with this credential offers the server, in order;
    /// the agent's keys add the time they wait for the agent to `agentWait`.
    func offers(agentWait: AgentWait) throws -> [SignInOffer] {
        switch self {
        case let .password(password):
            [SignInOffer(password: password)]
        case let .privateKey(key):
            try [SignInOffer(key.offers())].compactMap(\.self)
        case let .agent(agent):
            try agent.offers(wait: agentWait).compactMap { keys in
                var offer = SignInOffer(keys)
                offer?.usesAgent = true
                return offer
            }
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
