//
//  KnownHosts.swift
//  RayonModule
//
//  The host keys of the servers connected to so far, kept in the database.
//  A key is saved once the person has trusted it; after that a connection to
//  the same address is only made when the server presents the same key, so
//  someone answering in the server's place is refused instead of being
//  handed the password.
//

import Foundation
import RayonSSH
import Logger

public final class KnownHosts: Sendable {
    public typealias HostKey = SSHHostKey

    public static let shared = KnownHosts(storage: .shared)

    private let storage: RayonStorage

    public init(storage: RayonStorage) {
        self.storage = storage
    }

    /// Whether `offered` is the key saved for the address. A key an older
    /// release saved that the server still presents is this release's from
    /// now on: its grace for an Ed25519 key covers only the first
    /// connection after the upgrade, not one made months later by someone
    /// answering in the server's place.
    public func status(of offered: HostKey, host: String, port: Int) -> SSHHostKeyStatus {
        let name = Self.name(host: host, port: port)
        guard var record = storage.knownHost(named: name) else { return .unknown }
        let saved = HostKey(type: record.type, key: record.key)
        guard saved == offered else { return .changed(saved: saved) }
        if record.legacy {
            record.legacy = false
            do {
                try storage.saveKnownHost(record)
            } catch {
                Logger.database.errorFile("updating the host key of \(private: name) failed: \(error)")
            }
        }
        return .trusted
    }

    /// Saves `key` as the address's key, in place of any saved before; a
    /// key saved by an older release is no longer treated as one.
    public func trust(_ key: HostKey, host: String, port: Int) {
        let name = Self.name(host: host, port: port)
        do {
            try storage.saveKnownHost(KnownHostRecord(name: name, type: key.type, key: key.key, added: Date()))
        } catch {
            Logger.database.errorFile("saving the host key of \(private: name) failed: \(error)")
        }
    }

    /// What to ask the person about `offered`, a key that is not trusted.
    public func question(offering offered: HostKey, host: String, port: Int) -> HostKeyQuestion {
        let saved = storage.knownHost(named: Self.name(host: host, port: port))
        return HostKeyQuestion(
            host: host,
            port: port,
            offered: offered,
            saved: saved.map { HostKey(type: $0.type, key: $0.key) },
            savedByLegacyRelease: saved?.legacy ?? false
        )
    }

    public func savedKey(host: String, port: Int) -> HostKey? {
        storage.knownHost(named: Self.name(host: host, port: port)).map { HostKey(type: $0.type, key: $0.key) }
    }

    /// The next key the address presents is asked about again.
    public func forget(host: String, port: Int) {
        try? storage.removeKnownHost(named: Self.name(host: host, port: port))
    }

    public func forgetAll() {
        try? storage.removeAllKnownHosts()
    }

    public var count: Int {
        storage.knownHostCount
    }

    /// `[host]:port`, as known_hosts writes an address with a port.
    static func name(host: String, port: Int) -> String {
        "[\(host.trimmingCharacters(in: .whitespaces).lowercased())]:\(port)"
    }
}

public extension RDMachine {
    /// The next host key this server presents is asked about again.
    func forgetHostKey(in hosts: KnownHosts = .shared) {
        hosts.forget(host: remoteAddress, port: sshPort)
        HostKeyTrust.forgetDeclined(host: remoteAddress, port: sshPort)
    }
}
