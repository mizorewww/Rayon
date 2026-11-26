//
//  SSHAgent.swift
//  RayonSSH
//
//  Signing in with the keys an SSH agent holds (ssh-agent, or any agent
//  behind SSH_AUTH_SOCK), over the agent protocol: list the identities,
//  then ask the agent to sign. The private keys never leave the agent.
//
//  swift-nio-ssh asks a key for its signature synchronously, so the sign
//  request is a blocking round trip on the agent's local socket; an agent
//  that asks the person first (a confirmation, Touch ID) holds the
//  connection's event loop until it answers, at most `timeout`.
//

import Darwin
import Foundation
import NIOCore
import NIOSSH

public struct SSHAgent: Sendable {
    /// One key the agent holds.
    public struct Identity: Sendable, Equatable {
        /// The public key blob: its type, then the key.
        public let blob: [UInt8]
        public let comment: String

        /// The key's type, "ssh-ed25519" for one.
        public var type: String {
            var buffer = ByteBuffer(bytes: blob)
            return buffer.readSSHText() ?? ""
        }
    }

    public let socketPath: String
    public let timeout: TimeInterval

    public init(socketPath: String, timeout: TimeInterval = 30) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    // draft-miller-ssh-agent message numbers
    private static let failure: UInt8 = 5
    private static let requestIdentities: UInt8 = 11
    private static let identitiesAnswer: UInt8 = 12
    private static let signRequest: UInt8 = 13
    private static let signResponse: UInt8 = 14

    public func identities() throws -> [Identity] {
        var reply = try request(Self.requestIdentities, payload: ByteBuffer())
        guard reply.readInteger(as: UInt8.self) == Self.identitiesAnswer,
              let count = reply.readInteger(as: UInt32.self)
        else { throw SSHError.agentUnavailable("The SSH agent did not list its keys.") }
        var identities: [Identity] = []
        for _ in 0 ..< count {
            guard let blob = reply.readLengthPrefixedSlice(as: UInt32.self),
                  let comment = reply.readSSHText()
            else { throw SSHError.agentUnavailable("The SSH agent's list of keys is malformed.") }
            identities.append(Identity(blob: Array(blob.readableBytesView), comment: comment))
        }
        return identities
    }

    /// The agent's signature blob (its algorithm name, then the signature)
    /// of `data` with the key `blob`; `flags` picks rsa-sha2-256 (2) or
    /// rsa-sha2-512 (4) for an RSA key.
    func sign(_ data: some Collection<UInt8>, with blob: [UInt8], flags: UInt32) throws -> ByteBuffer {
        var payload = ByteBuffer()
        payload.writeSSHBytes(blob)
        payload.writeSSHBytes(data)
        payload.writeInteger(flags)
        var reply = try request(Self.signRequest, payload: payload)
        guard reply.readInteger(as: UInt8.self) == Self.signResponse,
              let signature = reply.readLengthPrefixedSlice(as: UInt32.self)
        else { throw SSHError.agentUnavailable("The SSH agent did not sign with the key.") }
        return signature
    }

    /// One request on a connection of its own.
    private func request(_ type: UInt8, payload: ByteBuffer) throws -> ByteBuffer {
        let socket = try connect()
        defer { close(socket) }
        var message = ByteBuffer()
        message.writeInteger(UInt32(payload.readableBytes + 1))
        message.writeInteger(type)
        message.writeImmutableBuffer(payload)
        try send(Array(message.readableBytesView), on: socket)
        let header = try receive(4, on: socket)
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= 256 * 1024 else {
            throw SSHError.agentUnavailable("The SSH agent sent a malformed reply.")
        }
        let body = try receive(length, on: socket)
        if body.first == Self.failure {
            throw SSHError.agentUnavailable("The SSH agent refused the request.")
        }
        return ByteBuffer(bytes: body)
    }

    private func connect() throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8)
        guard !path.isEmpty, path.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw SSHError.agentUnavailable("\"\(socketPath)\" is not an SSH agent socket.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path)
            raw[path.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw SSHError.agentUnavailable("Could not open a socket for the SSH agent.") }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let reason = String(cString: strerror(errno))
            close(socket)
            throw SSHError.agentUnavailable("Could not reach the SSH agent at \(socketPath) (\(reason)).")
        }
        return socket
    }

    private func send(_ bytes: [UInt8], on socket: Int32) throws {
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { Darwin.write(socket, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw SSHError.agentUnavailable("The SSH agent stopped answering.") }
            sent += count
        }
    }

    private func receive(_ length: Int, on socket: Int32) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        var received = 0
        while received < length {
            let count = bytes[received...].withUnsafeMutableBytes { Darwin.read(socket, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw SSHError.agentUnavailable("The SSH agent stopped answering.") }
            received += count
        }
        return bytes
    }
}

// MARK: Keys

extension SSHAgent {
    /// What signing in with the agent offers, key by key in the agent's
    /// order: an RSA key offers SHA-512, then SHA-256, then SHA-1
    /// signatures. Key types the agent holds but cannot sign in with here
    /// (certificates) are left out.
    func offers() throws -> [NIOSSHPrivateKey] {
        try identities().flatMap { identity -> [NIOSSHPrivateKey] in
            switch identity.type {
            case "ssh-ed25519": [key(AgentEd25519.self, identity)]
            case "ecdsa-sha2-nistp256": [key(AgentP256.self, identity)]
            case "ecdsa-sha2-nistp384": [key(AgentP384.self, identity)]
            case "ecdsa-sha2-nistp521": [key(AgentP521.self, identity)]
            case "sk-ssh-ed25519@openssh.com": [key(AgentSKEd25519.self, identity)]
            case "sk-ecdsa-sha2-nistp256@openssh.com": [key(AgentSKP256.self, identity)]
            case "ssh-rsa": [key(AgentRSASHA512.self, identity), key(AgentRSASHA256.self, identity), key(AgentRSASHA1.self, identity)]
            default: []
            }
        }
    }

    private func key<Algorithm: AgentAlgorithm>(_: Algorithm.Type, _ identity: Identity) -> NIOSSHPrivateKey {
        NIOSSHPrivateKey(custom: AgentKey<Algorithm>(agent: self, blob: identity.blob))
    }
}

/// How one kind of agent key is named and signed. swift-nio-ssh names a
/// custom key, its blob and its signature with one static prefix, so each
/// kind is a type; an RSA key is offered once per signature algorithm,
/// with that algorithm as its blob's type, as RSAUserKey does.
protocol AgentAlgorithm: Sendable {
    static var name: String { get }
    static var flags: UInt32 { get }
}

extension AgentAlgorithm {
    static var flags: UInt32 { 0 }
}

enum AgentEd25519: AgentAlgorithm { static let name = "ssh-ed25519" }
enum AgentP256: AgentAlgorithm { static let name = "ecdsa-sha2-nistp256" }
enum AgentP384: AgentAlgorithm { static let name = "ecdsa-sha2-nistp384" }
enum AgentP521: AgentAlgorithm { static let name = "ecdsa-sha2-nistp521" }
enum AgentSKEd25519: AgentAlgorithm { static let name = "sk-ssh-ed25519@openssh.com" }
enum AgentSKP256: AgentAlgorithm { static let name = "sk-ecdsa-sha2-nistp256@openssh.com" }
enum AgentRSASHA512: AgentAlgorithm {
    static let name = "rsa-sha2-512"
    static let flags: UInt32 = 4
}

enum AgentRSASHA256: AgentAlgorithm {
    static let name = "rsa-sha2-256"
    static let flags: UInt32 = 2
}

enum AgentRSASHA1: AgentAlgorithm { static let name = "ssh-rsa" }

final class AgentKey<Algorithm: AgentAlgorithm>: NIOSSHPrivateKeyProtocol, Sendable {
    static var keyPrefix: String { Algorithm.name }

    let agent: SSHAgent
    let blob: [UInt8]

    init(agent: SSHAgent, blob: [UInt8]) {
        self.agent = agent
        self.blob = blob
    }

    var publicKey: NIOSSHPublicKeyProtocol {
        AgentPublicKey<Algorithm>(blob: blob)
    }

    func signature<D: DataProtocol>(for data: D) throws -> NIOSSHSignatureProtocol {
        var signature = try agent.sign(Array(data), with: blob, flags: Algorithm.flags)
        guard signature.readSSHText() == Algorithm.name else {
            throw SSHError.agentUnavailable("The SSH agent signed with another algorithm than \(Algorithm.name).")
        }
        return AgentSignature<Algorithm>(rawRepresentation: Data(signature.readableBytesView))
    }
}

final class AgentPublicKey<Algorithm: AgentAlgorithm>: NIOSSHPublicKeyProtocol, Sendable {
    static var publicKeyPrefix: String { Algorithm.name }

    /// The blob after its type name, which swift-nio-ssh writes itself.
    let body: [UInt8]

    init(blob: [UInt8]) {
        var buffer = ByteBuffer(bytes: blob)
        _ = buffer.readSSHText()
        body = Array(buffer.readableBytesView)
    }

    private init(body: [UInt8]) {
        self.body = body
    }

    var rawRepresentation: Data { Data(body) }

    /// Never asked of a client's own key.
    func isValidSignature<D: DataProtocol>(_: NIOSSHSignatureProtocol, for _: D) -> Bool { false }

    func write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeBytes(body)
    }

    static func read(from buffer: inout ByteBuffer) throws -> Self {
        Self(body: buffer.readBytes(length: buffer.readableBytes) ?? [])
    }
}

/// The signature after its algorithm name, as the agent made it (for a
/// security key, with its flags and counter).
struct AgentSignature<Algorithm: AgentAlgorithm>: NIOSSHSignatureProtocol, Sendable {
    static var signaturePrefix: String { Algorithm.name }

    let rawRepresentation: Data

    func write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeBytes(rawRepresentation)
    }

    static func read(from buffer: inout ByteBuffer) throws -> Self {
        Self(rawRepresentation: Data(buffer.readBytes(length: buffer.readableBytes) ?? []))
    }
}
