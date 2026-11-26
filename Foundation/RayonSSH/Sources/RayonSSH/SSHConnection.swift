//
//  SSHConnection.swift
//  RayonSSH
//
//  One authenticated SSH connection. Everything that talks to the server —
//  shells, commands, SFTP, forwards, tunnels — is a channel on it.
//

@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH

public actor SSHConnection {
    public struct Configuration: Sendable {
        /// The server's address and port: where TCP connects, what a jump
        /// host forwards to, and what the host key is saved under.
        public var host: String
        public var port: Int
        public var username: String
        /// Offered in order until the server accepts one.
        public var credentials: [SSHCredential]
        public var transport: SSHTransport
        /// Bounds connecting, and opening each channel once connected.
        public var timeout: Duration
        /// How long the server may stay silent before it is asked whether
        /// it is still there; three asks unanswered close the connection.
        public var keepAliveInterval: Duration
        /// Compares the server's host key with the saved one. A key that is
        /// not trusted ends the connection before anything is sent.
        public var hostKeyStatus: @Sendable (SSHHostKey) -> SSHHostKeyStatus

        public init(
            host: String,
            port: Int,
            username: String,
            credentials: [SSHCredential],
            transport: SSHTransport = .tcp,
            timeout: Duration = .seconds(15),
            keepAliveInterval: Duration = .seconds(10),
            hostKeyStatus: @escaping @Sendable (SSHHostKey) -> SSHHostKeyStatus
        ) {
            self.host = host
            self.port = port
            self.username = username
            self.credentials = credentials
            self.transport = transport
            self.timeout = timeout
            self.keepAliveInterval = keepAliveInterval
            self.hostKeyStatus = hostKeyStatus
        }
    }

    private let client: SSHClient
    nonisolated let channel: Channel
    /// The server's identification line, "SSH-2.0-OpenSSH_9.6" for one.
    public nonisolated let serverVersion: String
    /// Kept open while this connection runs over it.
    private let bastion: SSHConnection?
    /// How long the server has to confirm a channel.
    private nonisolated let channelTimeout: TimeAmount

    private init(client: SSHClient, channel: Channel, serverVersion: String, bastion: SSHConnection?, channelTimeout: TimeAmount) {
        self.client = client
        self.channel = channel
        self.serverVersion = serverVersion
        self.bastion = bastion
        self.channelTimeout = channelTimeout
        // A jump host carries this connection alone, and ends with it.
        if let bastion {
            channel.closeFuture.whenComplete { _ in Task { await bastion.close() } }
        }
    }

    /// Connects and signs in, offering each credential in turn. Citadel
    /// asks a custom authentication delegate only once per connection, so
    /// every offer the server turns down costs a new connection.
    public static func connect(_ configuration: Configuration) async throws -> SSHConnection {
        let offers = try configuration.credentials.flatMap { try $0.offers() }
        guard !offers.isEmpty else { throw SSHError.authenticationFailed }
        var lastError: Error = SSHError.authenticationFailed
        for offer in offers {
            do {
                return try await connect(configuration, offering: offer)
            } catch SSHError.authenticationFailed {
                lastError = SSHError.authenticationFailed
                try Task.checkCancellation()
            }
        }
        throw lastError
    }

    private static func connect(
        _ configuration: Configuration,
        offering offer: NIOSSHUserAuthenticationOffer.Offer
    ) async throws -> SSHConnection {
        let timeout = TimeAmount(configuration.timeout)
        let channel = try await configuration.transport.makeChannel(
            host: configuration.host, port: configuration.port, timeout: timeout
        )
        let authenticator = SSHCredentialAuthenticator(username: configuration.username, offer: offer)
        var settings = SSHClientSettings(
            host: configuration.host,
            port: configuration.port,
            authenticationMethod: { .custom(authenticator) },
            hostKeyValidator: .custom(HostKeyValidator(status: configuration.hostKeyStatus))
        )
        settings.algorithms = algorithms
        let client: SSHClient
        do {
            client = try await withTaskExecutorPreference(EventLoopTaskExecutor(channel.eventLoop)) {
                try await SSHClient.connect(on: channel, settings: settings)
            }
        } catch {
            channel.close(promise: nil)
            throw Self.translate(error, host: configuration.host)
        }
        let keepAlive = TimeAmount(configuration.keepAliveInterval)
        let version = try? await channel.eventLoop.submit {
            try channel.pipeline.syncOperations.addHandler(SSHKeepalive(interval: keepAlive), position: .first)
            return try channel.pipeline.syncOperations.handler(type: SSHBannerGate.self).serverVersion
        }.get()
        let bastion: SSHConnection? = if case let .jump(connection) = configuration.transport { connection } else { nil }
        return SSHConnection(client: client, channel: channel, serverVersion: version ?? "", bastion: bastion, channelTimeout: timeout)
    }

    /// AES-GCM (built in) first, AES-CTR with non-EtM MACs for older
    /// servers. Neither is open to the Terrapin prefix truncation, which
    /// needs ChaCha20-Poly1305 or an EtM MAC. ssh-rsa host keys still
    /// verify for servers that offer nothing newer.
    private static var algorithms: SSHAlgorithms {
        var algorithms = SSHAlgorithms()
        algorithms.transportProtectionSchemes = .add([AES128CTR.self])
        algorithms.keyExchangeAlgorithms = .add([DiffieHellmanGroup14Sha256.self])
        algorithms.publicKeyAlgorihtms = .add([(Insecure.RSA.PublicKey.self, Insecure.RSA.Signature.self)])
        return algorithms
    }

    private static func translate(_ error: Error, host: String) -> Error {
        if let error = error as? SSHError { return error }
        if case ChannelError.connectTimeout = error {
            return SSHError.connectionFailed("Timed out signing in to \(host).")
        }
        if error is SSHClientError {
            return SSHError.authenticationFailed
        }
        return SSHError.connectionFailed("The connection to \(host) failed (\(SSHTransport.describe(error))).")
    }

    public nonisolated var isActive: Bool {
        channel.isActive
    }

    /// Completes when the connection closes, for whatever reason.
    public nonisolated var closed: EventLoopFuture<Void> {
        channel.closeFuture
    }

    public func close() async {
        try? await client.close()
    }

    public func openSFTP() async throws -> SFTPSession {
        do {
            return try await SFTPSession(client: client.openSFTP())
        } catch {
            throw SSHError.channelRejected("The server did not start SFTP (\(SSHTransport.describe(error))).")
        }
    }

    /// Runs Citadel's remote-forward request on this connection's client.
    func withRemotePortForward(
        host: String,
        port: Int,
        onOpen: @escaping @Sendable (SSHRemotePortForward) async throws -> Void,
        handleChannel: @escaping @Sendable (Channel, SSHChannelType.ForwardedTCPIP) -> EventLoopFuture<Void>
    ) async throws {
        try await client.withRemotePortForward(host: host, port: port, onOpen: onOpen, handleChannel: handleChannel)
    }

    // MARK: Channels

    /// Opens a child channel; `setup` runs on the event loop before any
    /// data arrives, and its result is returned once the server confirms.
    /// A server that does not confirm in time, or a cancelled task, fails
    /// the open and closes the channel if it opens later.
    nonisolated func openChannel<T: Sendable>(
        _ type: SSHChannelType,
        timeout: Duration? = nil,
        setup: @escaping @Sendable (Channel) throws -> T
    ) async throws -> T {
        let parent = channel
        let eventLoop = parent.eventLoop
        let outcome = eventLoop.makePromise(of: T.self)
        let deadline = eventLoop.scheduleTask(in: min(timeout.map(TimeAmount.init) ?? channelTimeout, channelTimeout)) {
            outcome.fail(SSHError.channelRejected("The server did not open a channel in time."))
        }
        outcome.futureResult.whenComplete { _ in deadline.cancel() }
        eventLoop.execute {
            let created = eventLoop.makePromise(of: Channel.self)
            let prepared = eventLoop.makePromise(of: T.self)
            created.futureResult.whenFailure { prepared.fail($0) }
            // Opened after all was given up on: nobody will use it.
            created.futureResult.whenSuccess { child in
                outcome.futureResult.whenFailure { _ in child.close(promise: nil) }
            }
            created.futureResult.flatMap { _ in prepared.futureResult }.cascade(to: outcome)
            do {
                let handler = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                handler.createChannel(created, channelType: type) { child, _ in
                    do {
                        prepared.succeed(try setup(child))
                        return child.eventLoop.makeSucceededVoidFuture()
                    } catch {
                        prepared.fail(error)
                        return child.eventLoop.makeFailedFuture(error)
                    }
                }
            } catch {
                created.fail(error)
            }
        }
        do {
            return try await withTaskCancellationHandler {
                try await outcome.futureResult.get()
            } onCancel: {
                outcome.fail(CancellationError())
            }
        } catch let error as SSHError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            throw parent.isActive
                ? SSHError.channelRejected("The server refused to open a channel (\(SSHTransport.describe(error))).")
                : SSHError.disconnected
        }
    }

    /// A direct-tcpip channel as raw bytes, for running another protocol
    /// (a jumped SSH connection) on it.
    nonisolated func openRawDirectTCPIP(
        host: String,
        port: Int,
        setup: @escaping @Sendable (Channel) throws -> Void
    ) async throws -> Channel {
        try await openChannel(Self.directTCPIP(host: host, port: port)) { child in
            try child.pipeline.syncOperations.addHandler(SSHChannelByteCodec())
            try setup(child)
            return child
        }
    }

    /// A direct-tcpip channel (`ssh -W host:port`) as an async byte stream
    /// whose outbound `finish()` sends EOF.
    public nonisolated func openDirectTCPIP(host: String, port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        try await openChannel(Self.directTCPIP(host: host, port: port)) { child in
            try child.allowHalfClosure()
            try child.pipeline.syncOperations.addHandler(SSHChannelByteCodec())
            return try NIOAsyncChannel(wrappingChannelSynchronously: child, configuration: .init(isOutboundHalfClosureEnabled: true))
        }
    }

    /// A direct-tcpip channel read on demand, for protocols that pull.
    public nonisolated func openByteStream(host: String, port: Int) async throws -> SSHByteStream {
        try await openChannel(Self.directTCPIP(host: host, port: port)) { child in
            try child.pipeline.syncOperations.addHandlers(SSHChannelByteCodec(), SSHByteStream.Reader())
            child.setOption(ChannelOptions.autoRead, value: false).whenComplete { _ in }
            return SSHByteStream(channel: child)
        }
    }

    /// A session channel, for a shell or a command.
    nonisolated func openSession(timeout: Duration? = nil) async throws -> NIOAsyncChannel<SSHSessionEvent, ByteBuffer> {
        try await openChannel(.session, timeout: timeout) { child in
            try child.allowHalfClosure()
            try child.pipeline.syncOperations.addHandler(SSHSessionHandler())
            return try NIOAsyncChannel(wrappingChannelSynchronously: child)
        }
    }

    private static func directTCPIP(host: String, port: Int) -> SSHChannelType {
        // The originator is informational; this side has no listening address.
        .directTCPIP(.init(targetHost: host, targetPort: port, originatorAddress: try! SocketAddress(ipAddress: "127.0.0.1", port: 0)))
    }
}

/// Checks the key the server presents against what is saved, synchronously,
/// so a decision never holds the handshake: an unknown or changed key ends
/// the attempt, and the caller asks the person before trying again.
private struct HostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    let status: @Sendable (SSHHostKey) -> SSHHostKeyStatus

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = SSHHostKey(hostKey)
        switch status(key) {
        case .trusted:
            validationCompletePromise.succeed()
        case .unknown:
            validationCompletePromise.fail(SSHError.unknownHostKey(key))
        case let .changed(saved):
            validationCompletePromise.fail(SSHError.hostKeyChanged(offered: key, saved: saved))
        }
    }
}

extension Channel {
    /// Lets each side of an SSH child channel end its writes on its own:
    /// the remote side's EOF arrives as an event instead of closing the
    /// channel, and this side's EOF after the remote's closes the channel.
    /// Must be called on the channel's event loop, before other handlers.
    func allowHalfClosure() throws {
        setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenComplete { _ in }
        try pipeline.syncOperations.addHandler(SSHHalfClosureGuard())
    }
}

/// swift-nio-ssh refuses an EOF sent after the peer's ("Sent EOF out of
/// sequence"), fails the channel's closeFuture with it, and NIOAsyncChannel
/// asserts that never happens. Once the peer has sent EOF both directions
/// are done, so sending ours is a full close instead.
final class SSHHalfClosureGuard: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = Any
    typealias OutboundIn = Any

    private var peerSentEOF = false

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case ChannelEvent.inputClosed = event { peerSentEOF = true }
        context.fireUserInboundEventTriggered(event)
    }

    func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        context.close(mode: mode == .output && peerSentEOF ? .all : mode, promise: promise)
    }
}
