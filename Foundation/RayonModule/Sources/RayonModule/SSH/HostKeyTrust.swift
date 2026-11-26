//
//  HostKeyTrust.swift
//  RayonModule
//
//  Asks the person before a server's host key is trusted: the first time
//  a server is seen, with its fingerprint to compare, and — as a warning —
//  when a server presents a key other than the saved one. One change is
//  asked about calmly, like a first key: a key saved by a release before
//  2.9 was the ECDSA or RSA one libssh2 asked for, and swift-nio-ssh asks
//  for Ed25519 first, so every such server presents its Ed25519 key once.
//  Any other change of key, of type included, is what someone answering
//  in the server's place would present. Each app registers how it asks at
//  launch; without one, nothing new is trusted.
//

import Foundation
import os
import RayonSSH

public struct HostKeyQuestion: Sendable {
    public let host: String
    public let port: Int
    public let offered: SSHHostKey
    /// The key saved for the address, when the offered one replaces it.
    public let saved: SSHHostKey?
    /// The saved key was saved by a release before 2.9.
    public let savedByLegacyRelease: Bool

    public init(host: String, port: Int, offered: SSHHostKey, saved: SSHHostKey?, savedByLegacyRelease: Bool = false) {
        self.host = host
        self.port = port
        self.offered = offered
        self.saved = saved
        self.savedByLegacyRelease = savedByLegacyRelease
    }

    /// The saved key was replaced by one this version of Rayon does not
    /// simply prefer: perhaps someone is intercepting the connection.
    public var isWarning: Bool {
        guard let saved else { return false }
        return !(savedByLegacyRelease && Self.libssh2Preferred(saved.type) && offered.type == "ssh-ed25519")
    }

    /// The host key types libssh2 asked for before Ed25519.
    private static func libssh2Preferred(_ type: String) -> Bool {
        type.hasPrefix("ecdsa-sha2-") || type == "ssh-rsa"
    }

    public var title: String {
        isWarning
            ? "WARNING: the host key of \(host) has changed"
            : "Trust \(host)?"
    }

    public var message: String {
        let name = port == 22 ? host : "\(host):\(port)"
        let compare = "Compare the key's fingerprint with the server's own (ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub) before trusting it.\n\n\(offered.type)\n\(offered.fingerprint)"
        guard let saved else {
            return "Rayon has not connected to \(name) before. " + compare
        }
        guard isWarning else {
            return "Rayon saved the \(saved.type) key of \(name); the server now presents its \(offered.type) key, which Rayon has not seen. Servers have a key of each type, and this version of Rayon asks for Ed25519 first. " + compare
        }
        return "\(name) presented a different host key than the one saved for it. Someone may be intercepting the connection. Only replace the saved key if you know the server was reinstalled or its keys were changed.\n\nSaved: \(saved.type)\n\(saved.fingerprint)\n\nOffered: \(offered.type)\n\(offered.fingerprint)"
    }

    public var confirmTitle: String {
        isWarning ? "Replace Saved Key" : "Trust and Connect"
    }
}

public protocol HostKeyTrustHandler: AnyObject, Sendable {
    /// Shows the question and answers whether the key is to be trusted.
    /// Called on the main actor.
    @MainActor func confirm(_ question: HostKeyQuestion) async -> Bool
}

public enum HostKeyTrust {
    private struct Asked: Hashable {
        let host: String
        let port: Int
        let key: SSHHostKey
    }

    private struct State {
        var handler: HostKeyTrustHandler?
        /// Questions on screen: whoever asks the same meanwhile waits for
        /// that answer instead of raising a second prompt.
        var pending: [Asked: Task<Bool, Never>] = [:]
        /// Keys the person turned down, not asked about again while the
        /// app runs: reconnecting features (the monitor, forwards) would
        /// otherwise raise the prompt every few seconds.
        var declined: Set<Asked> = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Registered once at app launch.
    public static var handler: HostKeyTrustHandler? {
        get { state.withLock { $0.handler } }
        set { state.withLock { $0.handler = newValue } }
    }

    /// Asks the registered handler; false when there is none, or when the
    /// person already turned this key down.
    static func confirm(_ question: HostKeyQuestion) async -> Bool {
        let asked = Asked(host: question.host, port: question.port, key: question.offered)
        let task = state.withLock { state -> Task<Bool, Never>? in
            guard !state.declined.contains(asked), let handler = state.handler else { return nil }
            if let pending = state.pending[asked] { return pending }
            let task = Task { await handler.confirm(question) }
            state.pending[asked] = task
            return task
        }
        guard let task else { return false }
        let trusted = await task.value
        state.withLock { state in
            state.pending[asked] = nil
            if !trusted { state.declined.insert(asked) }
        }
        return trusted
    }

    /// The keys of the address turned down so far are asked about again.
    static func forgetDeclined(host: String, port: Int) {
        state.withLock { $0.declined = $0.declined.filter { $0.host != host || $0.port != port } }
    }
}
