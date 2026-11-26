//
//  SSHConnection+Forwarding.swift
//  RayonSSH
//
//  `ssh -L`, `ssh -R` and `ssh -D`. Each forwarded connection is two async
//  channels copied into each other: a write waits while the other side
//  cannot take more, an EOF from either side is passed on as an EOF, and
//  both close once both directions are done.
//

import NIOCore
import NIOSSH
import NIOTransportServices

public extension SSHConnection {
    /// Listens on `127.0.0.1:bindPort` and forwards each connection to
    /// `targetHost:targetPort` as the server sees it. Runs until cancelled
    /// or until the connection closes.
    nonisolated func runLocalForward(
        bindPort: Int,
        targetHost: String,
        targetPort: Int,
        onListening: @escaping @Sendable () -> Void = {}
    ) async throws {
        let listener = try await Self.listen(port: bindPort) { channel in
            try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel, configuration: .init(isOutboundHalfClosureEnabled: true))
        }
        onListening()
        try await untilClosed {
            try await listener.executeThenClose { clients in
                try await withThrowingDiscardingTaskGroup { group in
                    for try await client in clients {
                        group.addTask {
                            do {
                                let remote = try await self.openDirectTCPIP(host: targetHost, port: targetPort)
                                await Self.bridge(client, remote)
                            } catch {
                                try? await client.channel.close()
                            }
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
        let (incoming, continuation) = AsyncStream<NIOAsyncChannel<ByteBuffer, ByteBuffer>>.makeStream()
        defer { continuation.finish() }
        try await untilClosed {
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask {
                    await withDiscardingTaskGroup { connections in
                        for await forwarded in incoming {
                            connections.addTask {
                                do {
                                    let local = try await Self.connect(host: targetHost, port: targetPort)
                                    await Self.bridge(forwarded, local)
                                } catch {
                                    try? await forwarded.channel.close()
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
                            continuation.yield(try NIOAsyncChannel(wrappingChannelSynchronously: channel, configuration: .init(isOutboundHalfClosureEnabled: true)))
                        }
                    }
                )
                continuation.finish()
            }
        }
    }

    /// A SOCKS5 proxy on `127.0.0.1:bindPort` whose CONNECT requests are
    /// made from the server (`ssh -D`).
    nonisolated func runDynamicForward(bindPort: Int, onListening: @escaping @Sendable () -> Void = {}) async throws {
        let listener = try await Self.listen(port: bindPort) { channel in
            let target = channel.eventLoop.makePromise(of: SOCKS5Handshake.Target.self)
            try channel.pipeline.syncOperations.addHandler(SOCKS5Handshake(target: target))
            return PendingSOCKS(channel: channel, target: target.futureResult)
        }
        onListening()
        try await untilClosed {
            try await listener.executeThenClose { clients in
                try await withThrowingDiscardingTaskGroup { group in
                    for try await client in clients {
                        group.addTask { await self.serveSOCKS(client) }
                    }
                }
            }
        }
    }

    private nonisolated func serveSOCKS(_ client: PendingSOCKS) async {
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
            let local = try await channel.eventLoop.submit {
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
        } catch {
            throw SSHError.connectionFailed("Could not listen on port \(port) (\(SSHTransport.describe(error))).")
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

private struct PendingSOCKS: Sendable {
    let channel: Channel
    let target: EventLoopFuture<SOCKS5Handshake.Target>
}
