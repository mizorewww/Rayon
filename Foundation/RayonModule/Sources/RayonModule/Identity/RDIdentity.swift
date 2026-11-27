//
//  RDIdentity.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDIdentity: StoredRecord {
    public static let tableName = "Identity"

    public struct Secrets: RecordSecrets {
        public var password = ""
        public var privateKey = ""

        public init() {}
    }

    public var id = UUID()

    public var username = ""
    public var publicKey = ""

    /// When it last signed a session in, on this device.
    public var lastRecentUsed = Date()
    public var comment = ""
    public var group = ""
    public var authenticAutomatically = true
    /// Signs in with the keys of the SSH agent instead of its own.
    public var useSSHAgent = false

    public var modified = Date()
    public var removed = false
    public var secrets = Secrets()
    public var secretsUnread = false

    public var password: String {
        get { secrets.password }
        set { secrets.password = newValue }
    }

    public var privateKey: String {
        get { secrets.privateKey }
        set { secrets.privateKey = newValue }
    }

    public init(
        id: UUID = .init(),
        username: String = "",
        password: String = "",
        privateKey: String = "",
        publicKey: String = "",
        lastRecentUsed: Date = .init(),
        comment: String = "",
        group: String = "",
        authenticAutomatically: Bool = true,
        useSSHAgent: Bool = false
    ) {
        self.id = id
        self.username = username
        self.publicKey = publicKey
        self.lastRecentUsed = lastRecentUsed
        self.comment = comment
        self.group = group
        self.authenticAutomatically = authenticAutomatically
        self.useSSHAgent = useSSHAgent
        secrets.password = password
        secrets.privateKey = privateKey
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDIdentity
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
        }

        case id
        case username
        case publicKey
        case lastRecentUsed
        case comment
        // "group" is an SQL keyword.
        case group = "groupName"
        case authenticAutomatically
        case useSSHAgent
        case modified
        case removed
    }

    public var syncedContent: RDIdentity {
        var content = self
        content.lastRecentUsed = .distantPast
        return content
    }

    public func keepingLocalState(of local: RDIdentity) -> RDIdentity {
        var merged = self
        merged.lastRecentUsed = local.lastRecentUsed
        return merged
    }

    public func shortDescription() -> String {
        guard username.count > 0 else {
            return String(localized: "Unknown Error", bundle: .module)
        }
        var build = String(localized: "User \(username) with \(getKeyType())", bundle: .module)
        if group.count > 0 {
            build += " Group<\(group)>"
        }
        if comment.count > 0 {
            build += " (\(comment))"
        }
        return build
    }

    public func getKeyType() -> String {
        if useSSHAgent {
            return String(localized: "SSH Agent", bundle: .module)
        } else if privateKey.count > 0, publicKey.count > 0 {
            if password.count > 0 {
                return String(localized: "Key Pair", bundle: .module)
            } else {
                return String(localized: "Plain Key Pair", bundle: .module)
            }
        } else if privateKey.count > 0 {
            if password.count > 0 {
                return String(localized: "Private Key", bundle: .module)
            } else {
                return String(localized: "Plain Private Key", bundle: .module)
            }
        } else if publicKey.count > 0 {
            return String(localized: "Unknown Key", bundle: .module)
        } else if password.count > 0 {
            return String(localized: "Password", bundle: .module)
        } else {
            return String(localized: "Username Only", bundle: .module)
        }
    }

    /// The user name this identity signs in as: `override` when the server
    /// sets its own, else the identity's.
    public func loginUsername(override: String?) -> String {
        guard let override, !override.isEmpty else { return username }
        return override
    }
}

public extension RDIdentity {
    /// "Key pair · ed25519", "Password", "SSH Agent" style description.
    var authDescription: String {
        if useSSHAgent { return String(localized: "SSH Agent", bundle: .module) }
        if !privateKey.isEmpty {
            if let type = keyAlgorithm { return String(localized: "Key pair · \(type)", bundle: .module) }
            return String(localized: "Key pair", bundle: .module)
        }
        if !password.isEmpty { return String(localized: "Password", bundle: .module) }
        return String(localized: "No credentials", bundle: .module)
    }

    var keyAlgorithm: String? {
        let source = publicKey.isEmpty ? privateKey : publicKey
        for (marker, name) in [("ssh-ed25519", "ed25519"), ("ecdsa-sha2", "ecdsa"), ("ssh-rsa", "rsa"), ("BEGIN RSA", "rsa"), ("BEGIN EC", "ecdsa")] {
            if source.contains(marker) { return name }
        }
        return nil
    }
}
