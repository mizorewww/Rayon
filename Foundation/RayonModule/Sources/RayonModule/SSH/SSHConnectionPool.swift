//
//  SSHConnectionPool.swift
//  RayonModule
//
//  One SSH connection per server, shared: the terminal, files, monitor,
//  forwards, snippets and the VNC tunnel each lease it and open their own
//  channels on it. The connection closes when the last lease is released,
//  and a lease taken after it dropped connects again.
//

import CryptoKit
import Foundation
import os
import RayonSSH

public actor SSHConnectionPool {
    public static let shared = SSHConnectionPool()

    private struct Entry {
        let id = UUID()
        let connecting: Task<(SSHConnection, RDIdentity), Error>
        var leases = 0
    }

    private var entries: [String: Entry] = [:]

    /// A lease on the server's connection, connecting when there is none.
    /// `hint` hears about each identity tried while connecting.
    public func lease(for machine: RDMachine, hint: (@Sendable (String) -> Void)? = nil) async throws -> SSHLease {
        let key = Self.key(for: machine)
        if let entry = entries[key] {
            // A connection that has dropped since is replaced. One that is
            // still connecting is shared even when it fails: those who
            // waited for it share the failure rather than each connecting
            // (and asking about the host key) again.
            if case let .success((connection, _)) = await entry.connecting.result,
               !connection.isActive, entries[key]?.id == entry.id
            {
                entries[key] = nil
            }
        }
        let entry: Entry
        if let existing = entries[key] {
            entry = existing
        } else {
            entry = Entry(connecting: Task { try await machine.connectSSH(hint: hint) })
            entries[key] = entry
        }
        entries[key]?.leases += 1
        do {
            let (connection, identity) = try await entry.connecting.value
            return SSHLease(connection: connection, identity: identity) { [weak self] in
                await self?.release(key: key, id: entry.id)
            }
        } catch {
            if entries[key]?.id == entry.id {
                entries[key]?.leases -= 1
                if entries[key]?.leases == 0 { entries[key] = nil }
            }
            throw error
        }
    }

    private func release(key: String, id: UUID) async {
        guard var entry = entries[key], entry.id == id else { return }
        entry.leases -= 1
        guard entry.leases <= 0 else {
            entries[key] = entry
            return
        }
        entries[key] = nil
        if let (connection, _) = try? await entry.connecting.value {
            await connection.close()
        }
    }

    /// Everything that decides how the server is reached and signed in to,
    /// down to the identities' secrets: a connection signed in with a
    /// password or key since changed is not handed out again.
    private static func key(for machine: RDMachine) -> String {
        let identities = machine.associatedIdentity == nil
            ? RayonStore.workerIdentitiesForAutoAuth
            : RayonStore.workerAssociatedIdentity(for: machine).map { [$0] } ?? []
        return [
            machine.id.uuidString,
            machine.remoteAddress,
            machine.remotePort,
            machine.sshUsername,
            machine.associatedIdentity?.uuidString ?? "",
            "\(machine.transport)",
            machine.proxyJumpMachineID?.uuidString ?? "",
            machine.uuDeviceID,
            secretsFingerprint([machine.cloudflareServiceTokenID, machine.cloudflareServiceTokenSecret], identities),
        ].joined(separator: "\u{1F}")
    }

    /// A SHA-256 digest of what the identities sign in with and of
    /// `fields`, so the key never holds a secret itself.
    static func secretsFingerprint(_ fields: [String], _ identities: [RDIdentity]) -> String {
        var hash = SHA256()
        let values = fields + identities.flatMap { identity in
            [identity.id.uuidString, identity.username, identity.password, identity.privateKey, identity.useSSHAgent ? "agent" : ""]
        }
        for value in values {
            hash.update(data: Data(value.utf8))
            hash.update(data: Data([0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A share of a pooled connection. Release it when done; one that is
/// dropped unreleased is released then.
public final class SSHLease: Sendable {
    public let connection: SSHConnection
    /// The identity the connection signed in with.
    public let identity: RDIdentity
    private let releaser: OSAllocatedUnfairLock<(@Sendable () async -> Void)?>

    init(connection: SSHConnection, identity: RDIdentity, release: @escaping @Sendable () async -> Void) {
        self.connection = connection
        self.identity = identity
        releaser = OSAllocatedUnfairLock(initialState: release)
    }

    public func release() {
        guard let release = releaser.withLock({ value in defer { value = nil }; return value }) else { return }
        Task { await release() }
    }

    deinit {
        release()
    }
}
