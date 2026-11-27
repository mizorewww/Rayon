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

extension RDIdentity {
    var telemetryAuthMethod: TelemetryReport.AuthMethod {
        if useSSHAgent { return .agent }
        return privateKey.isEmpty ? .password : .publicKey
    }

    var telemetryKeyType: TelemetryReport.KeyType? {
        guard !useSSHAgent, !privateKey.isEmpty else { return nil }
        // The public key names its algorithm; a PEM private key's header may.
        let text = publicKey.isEmpty ? String(privateKey.prefix(64)) : String(publicKey.prefix(32))
        if text.contains("ed25519") { return .ed25519 }
        if text.contains("ecdsa") || text.contains("BEGIN EC ") { return .ecdsa }
        if text.contains("rsa") || text.contains("BEGIN RSA ") { return .rsa }
        return nil
    }
}

extension TelemetryReport.ConnectionOutcome {
    /// RayonSSH words a transport failure for the person; these are the
    /// phrases SSHTransport.describe uses for each cause.
    init(reason: String) {
        let reason = reason.lowercased()
        self = if reason.contains("connection refused") {
            .refused
        } else if reason.contains("could not be found") {
            .dnsFailed
        } else if reason.contains("in time") || reason.contains("timed out") {
            .timeout
        } else {
            .other
        }
    }
}
