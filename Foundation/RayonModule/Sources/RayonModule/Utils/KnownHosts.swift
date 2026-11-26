//
//  KnownHosts.swift
//  RayonModule
//
//  The host keys of the servers connected to so far, kept in the database.
//  A server's key is saved the first time it is seen; after that a
//  connection to the same address is only made when the server presents the
//  same key, so someone answering in the server's place is refused instead
//  of being handed the password.
//

import CryptoKit
import Foundation
import NSRemoteShell
import os

public final class KnownHosts: Sendable {
    public struct HostKey: Equatable, Codable, Sendable {
        /// The algorithm as SSH names it, "ssh-ed25519" for one.
        public let type: String
        public let key: Data

        public init(type: String, key: Data) {
            self.type = type
            self.key = key
        }

        /// What `ssh-keygen -l` prints for the key.
        public var fingerprint: String {
            let digest = Data(SHA256.hash(data: key)).base64EncodedString()
            return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
        }
    }

    public static let shared = KnownHosts(storage: .shared)

    private let storage: RayonStorage
    /// The keys refused since launch, to tell the user what was offered. The
    /// lock also keeps a first sighting from racing another.
    private let refused = OSAllocatedUnfairLock<[String: HostKey]>(initialState: [:])

    public init(storage: RayonStorage) {
        self.storage = storage
    }

    /// Has every connection of `NSRemoteShell` checked against the saved keys.
    public static func install() {
        _ = installed
    }

    private static let installed: Void = {
        NSRemoteShell.hostKeyVerifier = { host, port, type, key in
            KnownHosts.shared.accepts(HostKey(type: type, key: key), host: host, port: port.intValue)
        }
    }()

    /// True for the key saved for the address, and for the first key seen
    /// there, which is saved. False for any other key.
    public func accepts(_ offered: HostKey, host: String, port: Int) -> Bool {
        let name = Self.name(host: host, port: port)
        return refused.withLock { refused in
            guard let saved = storage.knownHost(named: name) else {
                let record = KnownHostRecord(name: name, type: offered.type, key: offered.key, added: Date())
                do {
                    try storage.saveKnownHost(record)
                } catch {
                    RayonStorage.logger.error("saving the host key of \(name) failed: \(error.localizedDescription)")
                }
                refused[name] = nil
                return true
            }
            if HostKey(type: saved.type, key: saved.key) == offered {
                refused[name] = nil
                return true
            }
            refused[name] = offered
            return false
        }
    }

    public func savedKey(host: String, port: Int) -> HostKey? {
        storage.knownHost(named: Self.name(host: host, port: port)).map { HostKey(type: $0.type, key: $0.key) }
    }

    /// The key the address offered that was refused, if one was since launch.
    public func refusedKey(host: String, port: Int) -> HostKey? {
        refused.withLock { $0[Self.name(host: host, port: port)] }
    }

    /// The next key the address presents is saved as its key.
    public func forget(host: String, port: Int) {
        let name = Self.name(host: host, port: port)
        refused.withLock { refused in
            try? storage.removeKnownHost(named: name)
            refused[name] = nil
        }
    }

    public func forgetAll() {
        refused.withLock { refused in
            try? storage.removeAllKnownHosts()
            refused.removeAll()
        }
    }

    public var count: Int {
        storage.knownHostCount
    }

    /// Why a connection to the address was refused, when its host key was the
    /// reason; nil when it was not.
    public func refusalMessage(host: String, port: Int) -> String? {
        guard let offered = refusedKey(host: host, port: port) else { return nil }
        var lines = ["The host key of \(host):\(port) has changed, so the connection was refused."]
        if let saved = savedKey(host: host, port: port) {
            lines.append("Saved: \(saved.type) \(saved.fingerprint)")
        }
        lines.append("Offered: \(offered.type) \(offered.fingerprint)")
        lines.append("If the server was reinstalled or its keys were replaced, choose Forget Host Key for it and connect again. If not, something may be intercepting the connection.")
        return lines.joined(separator: "\n")
    }

    /// `[host]:port`, as known_hosts writes an address with a port.
    static func name(host: String, port: Int) -> String {
        "[\(host.trimmingCharacters(in: .whitespaces).lowercased())]:\(port)"
    }
}

public extension NSRemoteShell {
    /// Why the last connection was refused over the server's host key; nil
    /// when the host key was not the reason.
    var hostKeyRefusal: String? {
        KnownHosts.shared.refusalMessage(host: remoteHost, port: remotePort.intValue)
    }
}

public extension RDMachine {
    /// The next host key this server presents is saved as its key.
    func forgetHostKey() {
        KnownHosts.shared.forget(host: remoteAddress, port: Int(remotePort) ?? 0)
    }
}
