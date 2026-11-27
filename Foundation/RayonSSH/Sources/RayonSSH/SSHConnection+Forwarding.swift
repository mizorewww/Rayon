//
//  SSHConnection+Forwarding.swift
//  RayonSSH
//
//  `ssh -L`, `ssh -R` and `ssh -D`. Each forwarded connection is two async
//  channels copied into each other: a write waits while the other side
//  cannot take more, an EOF from either side is passed on as an EOF, and
//  both close once both directions are done.
//
//  A connection that waits for its other side (taken before signing in, or
//  while its channel opens) is held as a bare channel that reads nothing,
//  and becomes an async channel only to be bridged. A channel lets go of
//  an async channel's writer once it is active, so one made on accept and
//  then dropped unfinished trips NIO's "Deinited NIOAsyncWriter"
//  precondition.
//

import Network
import NIOCore
import NIOSSH
import NIOTransportServices

/// A port on this side listening for a forward, `ssh -L` or `ssh -D`.
/// It is bound before signing in, so that a port already in use costs no
/// connection; connections it takes meanwhile wait for the forward.
public struct SSHForwardListener: Sendable {
    fileprivate enum Kind: Sendable {
        case local(NIOAsyncChannel<Channel, Never>, targetHost: String, targetPort: Int)
        case dynamic(NIOAsyncChannel<PendingSOCKS, Never>)
    }

    fileprivate let kind: Kind

    /// Listens on `127.0.0.1:port` for connections forwarded to
    /// `targetHost:targetPort` as the server sees it.
    public static func local(port: Int, targetHost: String, targetPort: Int) async throws -> SSHForwardListener {
        let clients = try await listen(port: port) { channel in
            try SSHConnection.hold(channel)
            return channel
        }
        return SSHForwardListener(kind: .local(clients, targetHost: targetHost, targetPort: targetPort))
    }

    /// Listens on `127.0.0.1:port` as a SOCKS5 proxy whose CONNECT
    /// requests are made from the server.
    public static func dynamic(port: Int) async throws -> SSHForwardListener {
        let clients = try await listen(port: port) { channel in
            let target = channel.eventLoop.makePromise(of: SOCKS5Handshake.Target.self)
            try channel.pipeline.syncOperations.addHandler(SOCKS5Handshake(target: target))
            return PendingSOCKS(channel: channel, target: target.futureResult)
        }
        return SSHForwardListener(kind: .dynamic(clients))
    }

    /// Stops listening, for a listener no forward will run on, and closes
    /// the connections it took meanwhile.
    public func close() async {
        switch kind {
        case let .local(clients, _, _): await Self.close(clients) { $0 }
        case let .dynamic(clients): await Self.close(clients) { $0.channel }
        }
    }

    private static func close<Output: Sendable>(_ clients: NIOAsyncChannel<Output, Never>, _ channel: (Output) -> Channel) async {
        try? await clients.executeThenClose { waiting in
            // Once closed, the listener hands over what it took, then ends.
            try? await clients.channel.close()
            for try await client in waiting {
                try? await channel(client).close()
            }
        }
    }

    private static func listen<Output: Sendable>(
        port: Int,
        _ wrap: @escaping @Sendable (Channel) throws -> Output
    ) async throws -> NIOAsyncChannel<Output, Never> {
        do {
            return try await NIOTSListenerBootstrap(group: NIOTSEventLoopGroup.singleton)
                .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                .bind(host: "127.0.0.1", port: port) { channel in
                    channel.eventLoop.makeCompletedFuture { try wrap(channel) }
                }
        } catch NWError.posix(.EADDRINUSE) {
            throw SSHError.portInUse(port)
        } catch {
            throw SSHError.connectionFailed("Could not listen on port \(port) (\(SSHTransport.describe(error))).")
        }
    }
}

public extension SSHConnection {
    /// Forwards each connection `listener` takes through the server. Runs
    /// until cancelled or until the connection closes; the listener
    /// closes with it.
    nonisolated func runForward(_ listener: SSHForwardListener) async throws {
        try await untilClosed {
            switch listener.kind {
            case let .local(clients, targetHost, targetPort):
                try await clients.executeThenClose { clients in
                    try await withThrowingDiscardingTaskGroup { group in
                        for try await client in clients {
                            group.addTask {
                                do {
                                    let remote = try await self.openDirectTCPIP(host: targetHost, port: targetPort)
                                    await Self.bridge(held: client, remote)
                                } catch {
                                    try? await client.close()
                                }
                            }
                        }
                    }
                }
            case let .dynamic(clients):
                try await clients.executeThenClose { clients in
                    try await withThrowingDiscardingTaskGroup { group in
                        for try await client in clients {
                            group.addTask { await self.serveSOCKS(client) }
                        }
                    }
                }
            }
        }
    }

    /// Asks the server to listen on its `127.0.0.1:bindPort` and forwards
    /// each connection it takes to `targetHost:targetPort` from here.
    func runRemoteForward(
        bindPort: Int,
        targetHost: String,
        targetPort: Int,
        onListening: @escaping @Sendable () -> Void = {}
    ) async throws {
        let (incoming, continuation) = AsyncStream<Channel>.makeStream()
        defer { continuation.finish() }
        try await untilClosed {
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask {
                    await withDiscardingTaskGroup { connections in
                        for await forwarded in incoming {
                            connections.addTask {
                                do {
                                    let local = try await Self.connect(host: targetHost, port: targetPort)
                                    await Self.bridge(held: forwarded, local)
                                } catch {
                                    try? await forwarded.close()
                                }
                            }
                        }
                    }
                }
                try await self.withRemotePortForward(
                    host: "127.0.0.1",
                    port: bindPort,
                    onOpen: { _ in onListening() },
                    handleChannel: { channel, _ in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.allowHalfClosure()
                            try channel.pipeline.syncOperations.addHandler(SSHChannelByteCodec())
                            try Self.hold(channel)
                            if case .terminated = continuation.yield(channel) { channel.close(promise: nil) }
                        }
                    }
                )
                continuation.finish()
            }
        }
    }

    fileprivate nonisolated func serveSOCKS(_ client: PendingSOCKS) async {
        let channel = client.channel
        do {
            let target = try await client.target.get()
            let remote: NIOAsyncChannel<ByteBuffer, ByteBuffer>
            do {
                remote = try await openDirectTCPIP(host: target.host, port: target.port)
            } catch {
                try await channel.eventLoop.submit {
                    try channel.pipeline.syncOperations.handler(type: SOCKS5Handshake.self).refuse()
                }.get()
                return
            }
            let local: NIOAsyncChannel<ByteBuffer, ByteBuffer>
            do {
                local = try await channel.eventLoop.submit {
                    let sync = channel.pipeline.syncOperations
                    let handshake = try sync.handler(type: SOCKS5Handshake.self)
                    handshake.accept()
                    // Bytes the client sent past its request reach the async
                    // channel when the handshake leaves the pipeline.
                    let local = try NIOAsyncChannel<ByteBuffer, ByteBuffer>(
                        wrappingChannelSynchronously: channel, configuration: .init(isOutboundHalfClosureEnabled: true)
                    )
                    sync.removeHandler(handshake).whenComplete { _ in }
                    return local
                }.get()
            } catch {
                try? await remote.executeThenClose { _, _ in }
                throw error
            }
            await Self.bridge(local, remote)
        } catch {
            try? await channel.close()
        }
    }

    // MARK: Plumbing

    /// Runs `body` until it returns or the connection closes, whichever is first.
    private nonisolated func untilClosed(_ body: @escaping @Sendable () async throws -> Void) async throws {
        let closed = closed
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await closed.get()
                throw SSHError.disconnected
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    static func connect(host: String, port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        try await NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup.singleton)
            .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
            .connectTimeout(.seconds(15))
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel, configuration: .init(isOutboundHalfClosureEnabled: true))
                }
            }
    }

    /// Keeps a waiting connection from reading until `bridge(held:_:)`.
    static func hold(_ channel: Channel) throws {
        try channel.syncOptions?.setOption(ChannelOptions.autoRead, value: false)
    }

    /// Bridges a connection held by `hold` to `other`, closing both if the
    /// held one is already gone.
    static func bridge(held channel: Channel, _ other: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        let wrapped: NIOAsyncChannel<ByteBuffer, ByteBuffer>
        do {
            wrapped = try await channel.eventLoop.submit {
                let wrapped = try NIOAsyncChannel<ByteBuffer, ByteBuffer>(
                    wrappingChannelSynchronously: channel, configuration: .init(isOutboundHalfClosureEnabled: true)
                )
                try channel.syncOptions?.setOption(ChannelOptions.autoRead, value: true)
                // An SSH channel does not read again on its own.
                channel.read()
                return wrapped
            }.get()
        } catch {
            channel.close(promise: nil)
            try? await other.executeThenClose { _, _ in }
            return
        }
        await bridge(wrapped, other)
    }

    /// Copies each side into the other until both are done.
    static func bridge(_ first: NIOAsyncChannel<ByteBuffer, ByteBuffer>, _ second: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        try? await first.executeThenClose { firstInbound, firstOutbound in
            try await second.executeThenClose { secondInbound, secondOutbound in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await chunk in firstInbound { try await secondOutbound.write(chunk) }
                        secondOutbound.finish()
                    }
                    group.addTask {
                        for try await chunk in secondInbound { try await firstOutbound.write(chunk) }
                        firstOutbound.finish()
                    }
                    try await group.waitForAll()
                }
            }
        }
    }
}

fileprivate struct PendingSOCKS: Sendable {
    let channel: Channel
    let target: EventLoopFuture<SOCKS5Handshake.Target>
}
