//
//  SSHError.swift
//  RayonSSH
//

import Foundation

public enum SSHError: Error, Sendable, Equatable, LocalizedError {
    /// The server presented a key nothing is saved for; the person decides.
    case unknownHostKey(SSHHostKey)
    /// The server presented a key other than the one saved for its address.
    case hostKeyChanged(offered: SSHHostKey, saved: SSHHostKey)
    /// No credential offered was accepted.
    case authenticationFailed
    /// The server could not be reached, or the connection broke while it
    /// was made: the reason worded for the person, and its cause.
    case connectionFailed(String, cause: SSHConnectFailure)
    /// A private key could not be read.
    case unsupportedKey(String)
    /// The SSH agent could not be reached or would not sign.
    case agentUnavailable(String)
    /// The server refused to open a channel.
    case channelRejected(String)
    /// A command did not finish in time.
    case timedOut
    /// A command ended without the server telling how.
    case noExitStatus
    /// The connection closed.
    case disconnected
    /// A forward could not listen: another program has the port.
    case portInUse(Int)

    public var errorDescription: String? {
        switch self {
        case let .unknownHostKey(key):
            String(localized: "The server's host key is not known yet (\(key.type) \(key.fingerprint)).", bundle: .module)
        case let .hostKeyChanged(offered, saved):
            String(localized: "The server's host key has changed. Saved: \(saved.type) \(saved.fingerprint). Offered: \(offered.type) \(offered.fingerprint). If the server was reinstalled or its keys were replaced, forget its host key and connect again. If not, something may be intercepting the connection.", bundle: .module)
        case .authenticationFailed:
            String(localized: "The server did not accept any of the credentials.", bundle: .module)
        case let .connectionFailed(reason, _):
            reason
        case let .unsupportedKey(reason):
            reason
        case let .agentUnavailable(reason):
            reason
        case let .channelRejected(reason):
            reason
        case .timedOut:
            String(localized: "The command timed out.", bundle: .module)
        case .noExitStatus:
            String(localized: "The command ended without an exit status.", bundle: .module)
        case .disconnected:
            String(localized: "The connection closed.", bundle: .module)
        case let .portInUse(port):
            String(localized: "Port \(port) is already in use on this device.", bundle: .module)
        }
    }
}

/// Why a connection could not be made, by the error's type rather than
/// its wording, so the reason can be reworded freely.
public enum SSHConnectFailure: Sendable, Equatable {
    case refused, hostNotFound, timedOut, closed, other
}
