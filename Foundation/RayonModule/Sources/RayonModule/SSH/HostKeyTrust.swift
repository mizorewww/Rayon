//
//  HostKeyTrust.swift
//  RayonModule
//
//  Asks the person before a server's host key is trusted: the first time
//  a server is seen, with its fingerprint to compare, and — as a warning —
//  when a server presents a key other than the saved one. Each app
//  registers how it asks at launch; without one, nothing new is trusted.
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

    public var title: String {
        saved == nil
            ? "Trust \(host)?"
            : "WARNING: the host key of \(host) has changed"
    }

    public var message: String {
        let name = port == 22 ? host : "\(host):\(port)"
        guard let saved else {
            return "Rayon has not connected to \(name) before. Compare the key's fingerprint with the server's own (ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub) before trusting it.\n\n\(offered.type)\n\(offered.fingerprint)"
        }
        return "\(name) presented a different host key than the one saved for it. Someone may be intercepting the connection. Only replace the saved key if you know the server was reinstalled or its keys were changed.\n\nSaved: \(saved.type)\n\(saved.fingerprint)\n\nOffered: \(offered.type)\n\(offered.fingerprint)"
    }

    public var confirmTitle: String {
        saved == nil ? "Trust and Connect" : "Replace Saved Key"
    }
}

public protocol HostKeyTrustHandler: AnyObject, Sendable {
    /// Shows the question and answers whether the key is to be trusted.
    /// Called on the main actor.
    @MainActor func confirm(_ question: HostKeyQuestion) async -> Bool
}

public enum HostKeyTrust {
    private static let storage = OSAllocatedUnfairLock<HostKeyTrustHandler?>(initialState: nil)

    /// Registered once at app launch.
    public static var handler: HostKeyTrustHandler? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// Asks the registered handler; false when there is none.
    static func confirm(_ question: HostKeyQuestion) async -> Bool {
        guard let handler else { return false }
        return await handler.confirm(question)
    }
}
