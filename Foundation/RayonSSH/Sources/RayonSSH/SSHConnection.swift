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
import NIOPosix
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
        /// Bounds connecting and signing in.
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
    /// How long the server has to confirm a channel. Generous: on a link
    /// busy with output the confirmation queues behind it, and a link that
    /// is down is noticed by the keepalive sooner.
    private static let channelTimeout = TimeAmount.seconds(60)

    private init(client: SSHClient, channel: Channel, serverVersion: String, bastion: SSHConnection?) {
        self.client = client
        self.channel = channel
        self.serverVersion = serverVersion
        self.bastion = bastion
        // A jump host carries this connection alone, and ends with it.
        if let bastion {
            channel.closeFuture.whenComplete { _ in Task { await bastion.close() } }
        }
    }

    /// Connects and signs in, offering each credential in turn. Citadel
    /// asks a custom authentication delegate only once per connection, so
    /// every offer the server turns down costs a new connection.
    ///
    /// A jump host is given over: it closes with the connection, or right
    /// away when connecting fails or is cancelled.
    public static func connect(_ configuration: Configuration) async throws -> SSHConnection {
        do {
            return try await signIn(configuration)
        } catch {
            if case let .jump(bastion) = configuration.transport { await bastion.close() }
            throw error
        }
    }

    private static func signIn(_ configuration: Configuration) async throws -> SSHConnection {
        let agentWait = AgentWait()
        // Asking the agent for its keys is a blocking round trip on its
        // socket: off the threads Swift concurrency runs everything on.
        let credentials = configuration.credentials
        let offers = try await NIOThreadPool.singleton.runIfActive {
            try credentials.flatMap { try $0.offers(agentWait: agentWait) }
        }
        // Nothing was offered, so the server was not asked: an empty agent
        // is not the server turning the person down, and whoever reports
        // it still checks that the server can be reached.
        guard !offers.isEmpty else {
            let usesAgent = credentials.contains { if case .agent = $0 { true } else { false } }
            throw usesAgent ? SSHError.agentUnavailable("The SSH agent holds no keys.") : SSHError.authenticationFailed
        }
        var lastError: Error = SSHError.authenticationFailed
        var serverVersion: String?
        for offer in offers {
            for attempt in [offer.offer] + offer.fallbacks {
                do {
                    return try await connect(
                        configuration,
                        offering: attempt,
                        agentWait: offer.usesAgent ? agentWait : nil,
                        serverVersion: &serverVersion
                    )
                } catch SSHError.authenticationFailed {
                    lastError = SSHError.authenticationFailed
                    try Task.checkCancellation()
                    // A server that takes SHA-512 RSA signatures turned
                    // the key down, not the algorithm.
                    if takesRSASHA2(serverVersion) { break }
                } catch let error as AgentSignedAnotherAlgorithm {
                    lastError = error.sshError
                    try Task.checkCancellation()
                } catch let error as SSHError {
                    // The agent would not sign with the key (a declined
                    // confirmation, a cancelled Touch ID, a key it may not
                    // use here): the next key may do.
                    guard case .agentUnavailable = error else { throw error }
                    lastError = error
                    try Task.checkCancellation()
                    break
                }
            }
        }
        throw lastError
    }

    /// OpenSSH takes RSA keys' SHA-2 signatures since 7.2.
    static func takesRSASHA2(_ serverVersion: String?) -> Bool {
        guard let match = serverVersion?.firstMatch(of: /OpenSSH_(\d+)\.(\d+)/),
              let major = Int(match.1), let minor = Int(match.2)
        else { return false }
        return (major, minor) >= (7, 2)
    }

    /// One attempt with one offer. `serverVersion` is set to the server's
    /// identification once it is known, whether or not the attempt works.
    ///
    /// An offer the agent signs (`agentWait`) blocks its connection's event
    /// loop while the agent asks the person, so such a connection gets an
    /// event loop of its own where the transport allows, and the time the
    /// agent takes does not count against the timeout.
    private static func connect(
        _ configuration: Configuration,
        offering offer: NIOSSHUserAuthenticationOffer.Offer,
        agentWait: AgentWait?,
        serverVersion: inout String?
    ) async throws -> SSHConnection {
        let timeout = TimeAmount(configuration.timeout)
        let channel = try await configuration.transport.makeChannel(
            host: configuration.host, port: configuration.port, timeout: timeout, ownEventLoop: agentWait != nil
        )
        let gate: NIOLoopBound<SSHBannerGate>
        do {
            gate = try await channel.eventLoop.submit {
                try NIOLoopBound(channel.pipeline.syncOperations.handler(type: SSHBannerGate.self), eventLoop: channel.eventLoop)
            }.get()
        } catch {
            channel.close(promise: nil)
            throw SSHError.connectionFailed("The connection to \(configuration.host) closed (\(SSHTransport.describe(error))).")
        }
        let authenticator = SSHCredentialAuthenticator(username: configuration.username, offer: offer)
        var settings = SSHClientSettings(
            host: configuration.host,
            port: configuration.port,
            authenticationMethod: { .custom(authenticator) },
            hostKeyValidator: .custom(HostKeyValidator(status: configuration.hostKeyStatus))
        )
        settings.algorithms = algorithms
        // swift-nio-ssh opens each channel with a receive window of one
        // maximum packet, 128 KB by default: a download then waits for a
        // round trip every 128 KB. 2 MB is OpenSSH's window.
        settings.protocolOptions = [.maximumPacketSize(1 << 21)]
        // The handshake and sign-in get the connection's timeout too, and
        // end when the task is cancelled. Citadel gives up only after its
        // own 10 seconds, and a closed channel (one through a jump host
        // waits for the bastion to confirm) does not end it sooner, so
        // this does not wait for Citadel. The deadline is kept off the
        // channel's event loop, which a sign request to the agent holds.
        let signedIn = channel.eventLoop.makePromise(of: SSHClient.self)
        let started = ContinuousClock.now
        let waitedBefore = agentWait?.waited ?? .zero
        let deadline = Task {
            var limit = started + configuration.timeout
            while true {
                try await Task.sleep(until: limit, clock: .continuous)
                let extended = started + configuration.timeout + ((agentWait?.waited ?? .zero) - waitedBefore)
                guard extended > .now else { break }
                limit = extended
            }
            signedIn.fail(SSHError.connectionFailed("Timed out signing in to \(configuration.host)."))
        }
        signedIn.futureResult.whenComplete { _ in deadline.cancel() }
        signedIn.completeWithTask { [settings] in
            try await withTaskExecutorPreference(EventLoopTaskExecutor(channel.eventLoop)) {
                try await SSHClient.connect(on: channel, settings: settings)
            }
        }
        let client: SSHClient
        do {
            client = try await withTaskCancellationHandler {
                try await signedIn.futureResult.get()
            } onCancel: {
                signedIn.fail(CancellationError())
            }
        } catch {
            if let version = try? await channel.eventLoop.submit({ gate.value.serverVersion }).get() { serverVersion = version }
            channel.close(promise: nil)
            if error is CancellationError || error is AgentSignedAnotherAlgorithm { throw error }
            throw Self.translate(error, host: configuration.host)
        }
        let keepAlive = TimeAmount(configuration.keepAliveInterval)
        let version = try? await channel.eventLoop.submit {
            try channel.pipeline.syncOperations.addHandler(SSHKeepalive(interval: keepAlive), position: .first)
            return gate.value.serverVersion
        }.get()
        let bastion: SSHConnection? = if case let .jump(connection) = configuration.transport { connection } else { nil }
        return SSHConnection(client: client, channel: channel, serverVersion: version ?? "", bastion: bastion)
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

    /// Whether the server answers the keepalive's ask within `timeout`.
    /// Nothing runs on the server, so an account restricted to SFTP or
    /// git-shell answers as well as any: only a server out of reach does not.
    public nonisolated func answers(within timeout: Duration) async -> Bool {
        let channel = channel
        let eventLoop = channel.eventLoop
        let reply = eventLoop.makePromise(of: Void.self)
        let deadline = eventLoop.scheduleTask(in: TimeAmount(timeout)) { reply.fail(SSHError.timedOut) }
        reply.futureResult.whenComplete { _ in deadline.cancel() }
        channel.closeFuture.whenComplete { _ in reply.fail(SSHError.disconnected) }
        eventLoop.execute {
            guard let ssh = try? channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self) else {
                reply.fail(SSHError.disconnected)
                return
            }
            let answer = eventLoop.makePromise(of: GlobalRequest.TCPForwardingResponse?.self)
            ssh.sendTCPForwardingRequest(SSHKeepalive.ask, promise: answer)
            answer.futureResult.whenComplete { result in
                switch result {
                case .success:
                    reply.succeed()
                case let .failure(error as NIOSSHError) where error.type == .globalRequestRefused:
                    reply.succeed()
                case let .failure(error):
                    reply.fail(error)
                }
            }
        }
        return (try? await reply.futureResult.get()) != nil
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
        let deadline = eventLoop.scheduleTask(in: min(timeout.map(TimeAmount.init) ?? Self.channelTimeout, Self.channelTimeout)) {
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
/// sequence") and closes the channel with that error. Once the peer has
/// sent EOF both directions are done, so sending ours is a full close
/// instead.
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
