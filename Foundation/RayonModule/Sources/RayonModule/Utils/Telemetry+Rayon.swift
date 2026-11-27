//
//  Telemetry+Rayon.swift
//  RayonModule
//
//  Rayon's own types as telemetry enums: only the kind, never a value.
//

import Foundation
import RayonSSH

extension RDPortForward.ForwardOrientation {
    var telemetryKind: TelemetryReport.PortForwardKind {
        switch self {
        case .listenLocal: .local
        case .listenRemote: .remote
        case .dynamicSOCKS: .dynamic
        }
    }
}

public extension RDIdentity {
    var telemetryAuthMethod: TelemetryReport.AuthMethod {
        if useSSHAgent {
            return .agent
        }
        return privateKey.isEmpty ? .password : .publicKey
    }

    var telemetryKeyType: TelemetryReport.KeyType? {
        guard !useSSHAgent, !privateKey.isEmpty else { return nil }
        // The public key names its algorithm; a PEM private key's header may.
        let text = publicKey.isEmpty ? String(privateKey.prefix(64)) : String(publicKey.prefix(32))
        if text.contains("ed25519") {
            return .ed25519
        }
        if text.contains("ecdsa") || text.contains("BEGIN EC ") {
            return .ecdsa
        }
        if text.contains("rsa") || text.contains("BEGIN RSA ") {
            return .rsa
        }
        return nil
    }
}

extension TelemetryReport.ConnectionOutcome {
    init(_ cause: SSHConnectFailure) {
        self = switch cause {
        case .refused: .refused
        case .hostNotFound: .dnsFailed
        case .timedOut: .timeout
        case .closed, .other: .other
        }
    }
}
