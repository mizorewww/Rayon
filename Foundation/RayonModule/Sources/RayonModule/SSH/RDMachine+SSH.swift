//
//  RDMachine+SSH.swift
//  RayonModule
//
//  How a saved server is reached and signed in to: its transport (TCP,
//  Cloudflare Access, UU Remote, a ProxyJump chain), its identity or else
//  every identity that signs in automatically, and the host key, which is
//  only trusted once the person has seen its fingerprint.
//

import Foundation
import os
import RayonSSH

public extension RDMachine {
    /// Why signing in to a server failed, worded for the person.
    struct SSHFailure: Error, LocalizedError, Sendable {
        public let message: String
        /// The server could not be reached, as opposed to refusing the identities.
        public let unreachable: Bool

        public var errorDescription: String? { message }
    }

    /// Connects and signs in with `identity`, or else with each identity
    /// that authenticates automatically, one connection per identity.
    /// Returns the connection and the identity that signed in.
    ///
    /// A `background` connect (a reconnect nobody asked for) does not ask
    /// again about a host key the person turned down.
    func connectSSH(
        identity: RDIdentity?,
        autoIdentities: [RDIdentity],
        timeout: Duration,
        background: Bool = false,
        hint: (@Sendable (String) -> Void)? = nil
    ) async throws -> (SSHConnection, RDIdentity) {
        try await connectSSH(identity: identity, autoIdentities: autoIdentities, timeout: timeout, background: background, hint: hint, visited: [])
    }

    /// The machine's own identity when it has one, else the automatic ones;
    /// what the terminal, files, monitor, forwards and snippets all use.
    func connectSSH(
        timeout: Duration? = nil,
        background: Bool = false,
        hint: (@Sendable (String) -> Void)? = nil
    ) async throws -> (SSHConnection, RDIdentity) {
        let identity = RayonStore.workerAssociatedIdentity(for: self)
        if associatedIdentity != nil, identity == nil {
            throw SSHFailure(message: "The identity this server signs in with no longer exists.", unreachable: false)
        }
        return try await connectSSH(
            identity: identity,
            autoIdentities: RayonStore.workerIdentitiesForAutoAuth,
            timeout: timeout ?? .seconds(max(5, RayonStore.workerTimeoutNumber.intValue)),
            background: background,
            hint: hint
        )
    }

    private func connectSSH(
        identity: RDIdentity?,
        autoIdentities: [RDIdentity],
        timeout: Duration,
        background: Bool,
        hint: (@Sendable (String) -> Void)?,
        visited: Set<UUID>
    ) async throws -> (SSHConnection, RDIdentity) {
        let candidates = identity.map { [$0] } ?? autoIdentities
        var reasons: [String] = []
        /// Whether a server turned an identity down: it was reached.
        var reachedServer = false
        for candidate in candidates {
            // The name sshd sees: the server's override wins over the identity's.
            let username = candidate.loginUsername(override: sshUsernameOverride)
            let credentials: [SSHCredential]
            do {
                credentials = try candidate.sshCredentials()
            } catch {
                reasons.append("\(username) with \(candidate.signInDescription): \(error.localizedDescription)")
                continue
            }
            hint?("[i] Signing in as \(username) with \(candidate.signInDescription)")
            do {
                let connection = try await connect(
                    username: username,
                    credentials: credentials,
                    timeout: timeout,
                    background: background,
                    visited: visited
                )
                candidate.recordUse()
                return (connection, candidate)
            } catch SSHError.authenticationFailed {
                reachedServer = true
                reasons.append("\(username) with \(candidate.signInDescription) was not accepted.")
            } catch let SSHError.agentUnavailable(reason) {
                reasons.append("\(username) with \(candidate.signInDescription): \(reason)")
            }
        }
        // When no identity got as far as the server (there were none, or
        // none had a password or key), a server that cannot be reached
        // says so first: choosing another identity would not help.
        if !reachedServer {
            try await reach(timeout: timeout, background: background, visited: visited)
        }
        guard !candidates.isEmpty else {
            throw SSHFailure(message: "No identity to sign in with. Choose one for the server, or let an identity authenticate automatically.", unreachable: false)
        }
        throw SSHFailure(message: (["Could not sign in to \(name.isEmpty ? remoteAddress : name)."] + reasons).joined(separator: "\n"), unreachable: false)
    }

    /// Opens the server's transport without signing in; throws an
    /// unreachable failure when it cannot be opened.
    private func reach(timeout: Duration, background: Bool, visited: Set<UUID>) async throws {
        let transport = try await makeTransport(timeout: timeout, background: background, visited: visited)
        do {
            try await transport.reach(host: remoteAddress, port: sshPort, timeout: timeout)
        } catch let SSHError.connectionFailed(reason) {
            throw SSHFailure(message: transport.isWebSocket ? cloudflareReason(reason) : reason, unreachable: true)
        } catch let refusal as SSHWebSocketEndpoint.Refusal {
            throw SSHFailure(message: cloudflareReason(refusal), unreachable: true)
        } catch {
            throw SSHFailure(message: SSHTransport.describe(error), unreachable: true)
        }
    }

    /// The port connected to, and the host key saved under: 22 when the
    /// server's port is empty or not a number.
    var sshPort: Int {
        Int(remotePort) ?? 22
    }

    /// One connection attempt; asks about the host key and tries again
    /// when the person trusts it.
    private func connect(
        username: String,
        credentials: [SSHCredential],
        timeout: Duration,
        background: Bool,
        visited: Set<UUID>
    ) async throws -> SSHConnection {
        let host = remoteAddress
        let port = sshPort
        while true {
            let transport = try await makeTransport(timeout: timeout, background: background, visited: visited)
            let configuration = SSHConnection.Configuration(
                host: host,
                port: port,
                username: username,
                credentials: credentials,
                transport: transport,
                timeout: timeout,
                hostKeyStatus: { KnownHosts.shared.status(of: $0, host: host, port: port) }
            )
            do {
                return try await SSHConnection.connect(configuration)
            } catch let error as SSHError {
                switch error {
                case let .unknownHostKey(key):
                    guard await HostKeyTrust.confirm(KnownHosts.shared.question(offering: key, host: host, port: port), background: background) else {
                        throw SSHFailure(message: "The host key of \(host) was not trusted.", unreachable: true)
                    }
                    KnownHosts.shared.trust(key, host: host, port: port)
                case let .hostKeyChanged(offered, _):
                    guard await HostKeyTrust.confirm(KnownHosts.shared.question(offering: offered, host: host, port: port), background: background) else {
                        throw SSHFailure(message: error.localizedDescription, unreachable: true)
                    }
                    KnownHosts.shared.trust(offered, host: host, port: port)
                case .authenticationFailed, .agentUnavailable:
                    throw error
                case let .connectionFailed(reason):
                    throw SSHFailure(message: transport.isWebSocket ? cloudflareReason(reason) : reason, unreachable: true)
                default:
                    throw SSHFailure(message: error.localizedDescription, unreachable: true)
                }
            } catch let refusal as SSHWebSocketEndpoint.Refusal {
                throw SSHFailure(message: cloudflareReason(refusal), unreachable: true)
            }
        }
    }

    private func makeTransport(timeout: Duration, background: Bool, visited: Set<UUID>) async throws -> SSHTransport {
        switch transport {
        case .direct:
            return .tcp
        case .cloudflareAccess:
            var headers: [(String, String)] = []
            if !cloudflareServiceTokenID.isEmpty || !cloudflareServiceTokenSecret.isEmpty {
                headers = [("Cf-Access-Client-Id", cloudflareServiceTokenID), ("Cf-Access-Client-Secret", cloudflareServiceTokenSecret)]
            }
            let host = Self.cloudflareHostname(remoteAddress)
            guard !host.isEmpty else {
                throw SSHFailure(message: "\"\(remoteAddress)\" is not a host name Cloudflare can serve.", unreachable: true)
            }
            return .webSocket(SSHWebSocketEndpoint(host: host, headers: headers))
        case .uuRemote:
            let machine = self
            return .socket { try await machine.openUUSSHStream(timeout: timeout) }
        case .proxyJump:
            guard let jumpID = proxyJumpMachineID else {
                throw SSHFailure(message: "ProxyJump server is not selected.", unreachable: true)
            }
            var visited = visited
            visited.insert(id)
            guard !visited.contains(jumpID), visited.count <= 5 else {
                throw SSHFailure(message: "ProxyJump chain contains a loop.", unreachable: true)
            }
            guard let bastion = RayonStore.workerMachine(for: jumpID) else {
                throw SSHFailure(message: "The configured ProxyJump server no longer exists.", unreachable: true)
            }
            do {
                let (connection, _) = try await bastion.connectSSH(
                    identity: RayonStore.workerAssociatedIdentity(for: bastion),
                    autoIdentities: RayonStore.workerIdentitiesForAutoAuth,
                    timeout: timeout,
                    background: background,
                    hint: nil,
                    visited: visited
                )
                return .jump(connection)
            } catch let failure as SSHFailure {
                throw SSHFailure(message: "Jump host \(bastion.name): \(failure.message)", unreachable: true)
            }
        }
    }

    /// "https://host/" and "host:443" as typed are the host itself.
    static func cloudflareHostname(_ hostname: String) -> String {
        var host = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = host.range(of: "://") { host = String(host[range.upperBound...]) }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        if host.hasSuffix(":443") { host.removeLast(4) }
        return host
    }

    private func cloudflareReason(_ refusal: SSHWebSocketEndpoint.Refusal) -> String {
        let host = Self.cloudflareHostname(remoteAddress)
        let asksForSignIn = refusal.location?.contains("/cdn-cgi/access/") == true || [302, 401, 403].contains(refusal.status)
        guard asksForSignIn else { return "Could not open a Cloudflare tunnel to \(host) (HTTP \(refusal.status))." }
        if !cloudflareServiceTokenID.isEmpty {
            return "Cloudflare Access did not accept the service token for \(host). Check its Client ID and Secret, and that the application's policy allows it (Service Auth)."
        }
        return "\(host) is protected by Cloudflare Access and asks to sign in. Add a service token to the server (Edit Server › Cloudflare Access): signing in with a browser is not supported yet."
    }

    private func cloudflareReason(_ reason: String) -> String {
        "Could not open a Cloudflare tunnel to \(Self.cloudflareHostname(remoteAddress)): \(reason)"
    }
}

private extension SSHTransport {
    var isWebSocket: Bool {
        if case .webSocket = self { return true }
        return false
    }
}

extension RDIdentity {
    /// What this identity offers the server. A key's passphrase is the
    /// identity's password; a key identity does not offer the password.
    /// `environment` is where the agent's socket is found.
    func sshCredentials(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> [SSHCredential] {
        if useSSHAgent {
            #if os(macOS)
                // The agent of the person's login session, as ssh and
                // libssh2 find it; launchd sets it for every app.
                guard let socket = environment["SSH_AUTH_SOCK"], !socket.isEmpty else {
                    throw SSHFailure(message: "No SSH agent is running for this session (SSH_AUTH_SOCK is not set).", unreachable: false)
                }
                return [.agent(SSHAgent(socketPath: socket))]
            #else
                throw SSHFailure(message: "There is no SSH agent on iOS. Give the identity its private key instead.", unreachable: false)
            #endif
        }
        if !privateKey.isEmpty {
            return try [.privateKey(decryptedKey())]
        }
        if !password.isEmpty {
            return [.password(password)]
        }
        throw SSHFailure(message: "The identity has neither a password nor a private key.", unreachable: false)
    }

    /// What the identity signs in with, for a status line: its key type
    /// and, when it has them, its group and comment.
    var signInDescription: String {
        var text = getKeyType()
        if !group.isEmpty { text += " from \(group)" }
        if !comment.isEmpty { text += " (\(comment))" }
        return text
    }

    /// Stamps the identity as used, at most once a minute.
    func recordUse() {
        let id = id
        let date = Date()
        Task { @MainActor in RayonStore.shared.noteIdentityUsed(id, at: date) }
    }
}

private typealias SSHFailure = RDMachine.SSHFailure

extension RDIdentity {
    private struct DecryptedKey {
        let text: String
        let passphrase: String
        let key: SSHPrivateKey
    }

    /// Keys read so far, by identity, while the app runs: decrypting a key
    /// takes its bcrypt rounds on every connect otherwise.
    private static let decryptedKeys = OSAllocatedUnfairLock<[RDIdentity.ID: DecryptedKey]>(initialState: [:])

    /// The identity's private key, read once per key and passphrase.
    func decryptedKey() throws -> SSHPrivateKey {
        let cached = Self.decryptedKeys.withLock { $0[id] }
        if let cached, cached.text == privateKey, cached.passphrase == password { return cached.key }
        let key = try SSHPrivateKey(text: privateKey, passphrase: password)
        Self.decryptedKeys.withLock { $0[id] = DecryptedKey(text: privateKey, passphrase: password, key: key) }
        return key
    }
}
