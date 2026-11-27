//
//  RDIdentity+Deploy.swift
//  RayonModule
//
//  ssh-copy-id: appends an identity's public key to ~/.ssh/authorized_keys
//  on servers, so the identity's key signs in to them. Shared by macOS and
//  iOS; each app picks the servers and reports the outcome.
//

import Foundation
import RayonSSH

public enum PublicKeyDeployment {
    /// Which servers took the key and which did not, by name.
    public struct Outcome: Sendable {
        public var succeeded: [String] = []
        public var failed: [String] = []
    }

    /// The remote command: makes ~/.ssh and authorized_keys with the
    /// permissions sshd requires, and appends the key unless it is there.
    /// sh runs it, so it works whatever the server's login shell is. A
    /// public key is one line; a stray line break becomes a space.
    public static func installCommand(for publicKey: String) -> String {
        let pub = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let escapedKey = pub.replacingOccurrences(of: "'", with: "'\\''")
        return RemoteShellCommand.posix("umask 077 && mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '\(escapedKey)' ~/.ssh/authorized_keys || printf '%s\\n' '\(escapedKey)' >> ~/.ssh/authorized_keys)")
    }

    /// Installs `publicKey` on each server in turn, signing in as each
    /// server already does. A server counts as done only when the command
    /// exits 0; a failure, a timeout or no exit status is a failure.
    public static func deploy(_ publicKey: String, to machines: [RDMachine.ID]) async -> Outcome {
        let installCmd = installCommand(for: publicKey)
        var outcome = Outcome()
        for machineID in machines {
            guard let machine = RayonStore.workerMachine(for: machineID) else { continue }
            do {
                let lease = try await SSHConnectionPool.shared.lease(for: machine)
                defer { lease.release() }
                let result = try await lease.connection.execute(installCmd, timeout: .seconds(15))
                if result.status == 0 {
                    outcome.succeeded.append(machine.name)
                } else {
                    outcome.failed.append(machine.name)
                }
            } catch {
                outcome.failed.append(machine.name)
            }
        }
        return outcome
    }

    /// After a deployment every server took: the servers that sign in
    /// automatically now use the identity whose key they hold.
    @MainActor
    public static func adopt(identity: RDIdentity.ID, on machines: [RDMachine.ID]) {
        for machineID in machines {
            RayonStore.shared.updateMachine(machineID) { machine in
                if machine.associatedIdentity == nil { machine.associatedIdentity = identity }
            }
        }
    }
}

public extension IdentityDraft {
    /// Replaces the key pair with a new Ed25519 one, labelled with the
    /// comment, else user@Rayon.
    mutating func generateEd25519KeyPair() {
        let label = comment.isEmpty
            ? (username.isEmpty ? "Rayon" : "\(username)@Rayon")
            : comment
        let pair = RDIdentity.generateEd25519KeyPair(comment: label)
        privateKey = pair.privateKey
        publicKey = pair.publicKey
        passphrase = ""
    }
}
