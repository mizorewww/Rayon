//
//  SSHConnectionPool.swift
//  RayonModule
//
//  One SSH connection per server, shared: the terminal, files, monitor,
//  forwards, snippets and the VNC tunnel each lease it and open their own
//  channels on it. The connection closes when the last lease is released,
//  and a lease taken after it dropped connects again.
//

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
            // A connection that failed or has since dropped is replaced.
            let alive = (try? await entry.connecting.value)?.0.isActive ?? false
            if !alive, entries[key]?.id == entry.id { entries[key] = nil }
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

    /// Everything that decides how the server is reached and signed in to.
    private static func key(for machine: RDMachine) -> String {
        [
            machine.id.uuidString,
            machine.remoteAddress,
            machine.remotePort,
            machine.sshUsername,
            machine.associatedIdentity?.uuidString ?? "",
            "\(machine.transport)",
            machine.proxyJumpMachineID?.uuidString ?? "",
            machine.uuDeviceID,
            machine.cloudflareServiceTokenID,
        ].joined(separator: "\u{1F}")
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
