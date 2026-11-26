//
//  RDMachine.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/8.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDMachine: StoredRecord {
    public static let tableName = "Machine"

    public struct Secrets: RecordSecrets {
        public var vncPassword = ""
        public var cloudflareServiceTokenSecret = ""
        public var uuAssistCode = ""

        public init() {}
    }

    public var id = UUID()

    public var remoteAddress = ""
    public var remotePort = ""

    public var name = ""
    /// The folder the server is in; nil for the default one.
    public var folderId: UUID?
    /// When the server was last connected to, on this device.
    public var lastConnection = Date()
    /// What the server said last, on this device.
    public var lastBanner = ""
    public var comment = ""
    public var associatedIdentity: RDIdentity.ID?
    /// The user name to sign in as on this server. Empty means the
    /// identity's own; when set, it overrides the identity's user name, so
    /// one key can sign in as different users on different servers.
    public var sshUsername = ""

    public var fileTransferLoginPath = "/"
    public var transport: Transport = .direct
    public var cloudflareServiceTokenID = ""
    public var remoteDesktopProtocol: RemoteDesktopProtocolType = .none
    public var vncPort = "5900"
    public var vncUsername = ""
    public var vncShared = true
    public var vncOverSSH = false
    public var uuDeviceID = ""
    public var uuDeviceAlias = ""
    public var uuAnonymousDeviceID = ""
    public var uuAssistID = ""
    public var uuDisplayID = 0
    public var uuFPS = 60
    public var uuQuality = 5
    /// UU Remote's true colour: 4:4:4 chroma instead of 4:2:0.
    public var uuTrueColor = false
    public var uuManaged = false
    public var ghosttyTerminfoVersion: String?
    /// The server this one is reached through when `transport` is `.proxyJump`.
    public var proxyJumpMachineID: RDMachine.ID?

    public var modified = Date()
    public var removed = false
    public var secrets = Secrets()
    public var secretsUnread = false

    public var vncPassword: String {
        get { secrets.vncPassword }
        set { secrets.vncPassword = newValue }
    }

    public var cloudflareServiceTokenSecret: String {
        get { secrets.cloudflareServiceTokenSecret }
        set { secrets.cloudflareServiceTokenSecret = newValue }
    }

    public var uuAssistCode: String {
        get { secrets.uuAssistCode }
        set { secrets.uuAssistCode = newValue }
    }

    public init(
        id: UUID = UUID(),
        remoteAddress: String = "",
        remotePort: String = "",
        name: String = "",
        folderId: UUID? = nil,
        lastConnection: Date = .init(),
        lastBanner: String = "",
        comment: String = "",
        associatedIdentity: RDIdentity.ID? = nil,
        sshUsername: String = ""
    ) {
        self.id = id
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.name = name
        self.folderId = folderId
        self.lastConnection = lastConnection
        self.lastBanner = lastBanner
        self.comment = comment
        self.associatedIdentity = associatedIdentity
        self.sshUsername = sshUsername
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDMachine
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
            BindIndex(folderId, namedWith: "_folderIdIndex")
        }

        case id
        case remoteAddress
        case remotePort
        case name
        case folderId
        case lastConnection
        case lastBanner
        case comment
        case associatedIdentity
        case sshUsername
        case fileTransferLoginPath
        case transport
        case cloudflareServiceTokenID
        case remoteDesktopProtocol
        case vncPort
        case vncUsername
        case vncShared
        case vncOverSSH
        case uuDeviceID
        case uuDeviceAlias
        case uuAnonymousDeviceID
        case uuAssistID
        case uuDisplayID
        case uuFPS
        case uuQuality
        case uuTrueColor
        case uuManaged
        case ghosttyTerminfoVersion
        case proxyJumpMachineID
        case modified
        case removed
    }

    public var syncedContent: RDMachine {
        var content = self
        content.lastConnection = .distantPast
        content.lastBanner = ""
        return content
    }

    public func keepingLocalState(of local: RDMachine) -> RDMachine {
        var merged = self
        merged.lastConnection = local.lastConnection
        merged.lastBanner = local.lastBanner
        return merged
    }

    public func isQualifiedForSearch(text: String) -> Bool {
        let searchText = text.lowercased()
        return [remoteAddress, remotePort, name, lastBanner, comment]
            .contains { $0.lowercased().contains(searchText) }
    }

    public func shortDescription(withComment: Bool = true) -> String {
        if isUURemoteDevice { return name }
        var build = name + " "
        let username = sshLoginUsername(identity: RayonStore.workerAssociatedIdentity(for: self))
        if !username.isEmpty {
            build += username + "@"
        }
        build += remoteAddress
        if remotePort != "22" {
            build += " -p " + remotePort
        }
        if withComment, !comment.isEmpty {
            build += " (" + comment + ")"
        }
        return build
    }

    /// The server's own user name, trimmed; nil when it has none and the
    /// identity's user name applies.
    public var sshUsernameOverride: String? {
        let trimmed = sshUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The user name this server signs in as: its own when set, else the
    /// identity's, else empty.
    public func sshLoginUsername(identity: RDIdentity?) -> String {
        sshUsernameOverride ?? identity?.username ?? ""
    }

    /// Whether it has somewhere to connect to.
    public var hasAddress: Bool {
        !remoteAddress.isEmpty && !remotePort.isEmpty
    }

    public func getCommand(insertLeadingSSH: Bool = true) -> String {
        getCommand(insertLeadingSSH: insertLeadingSSH) { RayonStore.workerMachine(for: $0) }
    }

    /// The ssh command for the server; `lookup` finds the servers a proxy jump
    /// goes through. A jump chain that loops is left out of the command.
    public func getCommand(insertLeadingSSH: Bool = true, lookup: (RDMachine.ID) -> RDMachine?) -> String {
        let username = sshLoginUsername(identity: RayonStore.workerAssociatedIdentity(for: self))
        var target = username.isEmpty ? remoteAddress : "\(username)@\(remoteAddress)"
        if remotePort != "22" {
            target += " -p " + remotePort
        }
        guard insertLeadingSSH else { return target }
        if transport == .cloudflareAccess {
            return "ssh " + SSHCommandReader.cloudflareProxyOption + " " + target
        }
        if transport == .proxyJump, let jumps = try? proxyJumpChain(lookup: lookup), !jumps.isEmpty {
            let spec = jumps.map {
                $0.getCommand(insertLeadingSSH: false, lookup: lookup).replacingOccurrences(of: " -p ", with: ":")
            }
            return "ssh -J \(spec.joined(separator: ",")) " + target
        }
        return "ssh " + target
    }
}

// MARK: - Proxy jump

public extension RDMachine {
    enum ProxyJumpError: LocalizedError, Equatable {
        /// The chain comes back to a server it went through.
        case cycle(names: [String])

        public var errorDescription: String? {
            switch self {
            case let .cycle(names):
                "The proxy jumps go round in a circle: \(names.joined(separator: " → "))."
            }
        }
    }

    /// The servers a connection goes through, the first hop first; empty when
    /// the server is reached directly. Throws when the chain loops, which
    /// would otherwise never end.
    func proxyJumpChain(lookup: (RDMachine.ID) -> RDMachine?) throws -> [RDMachine] {
        var visited: [RDMachine.ID] = [id]
        var names = [name]
        var chain: [RDMachine] = []
        var current = self
        while current.transport == .proxyJump, let next = current.proxyJumpMachineID {
            guard let jump = lookup(next) else { break }
            names.append(jump.name)
            guard !visited.contains(jump.id) else { throw ProxyJumpError.cycle(names: names) }
            visited.append(jump.id)
            chain.insert(jump, at: 0)
            current = jump
        }
        return chain
    }
}
