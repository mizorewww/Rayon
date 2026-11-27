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
    /// The server could not be reached, or the connection broke while it was made.
    case connectionFailed(String)
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
            "The server's host key is not known yet (\(key.type) \(key.fingerprint))."
        case let .hostKeyChanged(offered, saved):
            "The server's host key has changed. Saved: \(saved.type) \(saved.fingerprint). Offered: \(offered.type) \(offered.fingerprint). If the server was reinstalled or its keys were replaced, forget its host key and connect again. If not, something may be intercepting the connection."
        case .authenticationFailed:
            "The server did not accept any of the credentials."
        case let .connectionFailed(reason):
            reason
        case let .unsupportedKey(reason):
            reason
        case let .agentUnavailable(reason):
            reason
        case let .channelRejected(reason):
            reason
        case .timedOut:
            "The command timed out."
        case .noExitStatus:
            "The command ended without an exit status."
        case .disconnected:
            "The connection closed."
        case let .portInUse(port):
            "Port \(port) is already in use on this device."
        }
    }
}
