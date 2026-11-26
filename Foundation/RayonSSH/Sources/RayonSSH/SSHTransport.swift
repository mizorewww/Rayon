//
//  SSHTransport.swift
//  RayonSSH
//
//  The byte stream an SSH session runs over: a TCP connection
//  (Network.framework), a WebSocket (Cloudflare Access), a socket another
//  component connected (UU Remote), or a direct-tcpip channel of another
//  connection (ProxyJump). Each ends in an `SSHBannerGate`, where the SSH
//  handlers go.
//

import Foundation
import Network
import NIOCore
import NIOPosix
import NIOTransportServices

public enum SSHTransport: Sendable {
    /// A TCP connection to the server's address and port.
    case tcp
    /// A WebSocket whose binary messages carry the SSH stream.
    case webSocket(SSHWebSocketEndpoint)
    /// A connected stream socket, opened afresh for each attempt; the
    /// connection owns and closes it. Read and written without blocking on
    /// the event loop, like any other socket.
    case socket(@Sendable () async throws -> Int32)
    /// A direct-tcpip channel opened on another connection.
    case jump(SSHConnection)
}

extension SSHTransport {
    /// With `ownEventLoop`, a TCP or WebSocket connection runs on an event
    /// loop of its own, ended when it closes, so that blocking it holds no
    /// other connection. A socket's and a jump's channel stay where they are.
    func makeChannel(host: String, port: Int, timeout: TimeAmount, ownEventLoop: Bool = false) async throws -> Channel {
        switch self {
        case .tcp:
            return try await Self.onEventLoopGroup(own: ownEventLoop) { group in
                try await Self.connectTCP(host: host, port: port, timeout: timeout, group: group)
            }
        case let .webSocket(endpoint):
            return try await Self.onEventLoopGroup(own: ownEventLoop) { group in
                try await endpoint.connect(timeout: timeout, group: group)
            }
        case let .socket(open):
            let descriptor = try await open()
            do {
                return try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                    .channelInitializer { channel in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(SSHBannerGate())
                        }
                    }
                    .withConnectedSocket(descriptor)
                    .get()
            } catch {
                close(descriptor)
                throw SSHError.connectionFailed("The tunnel to \(host):\(port) could not be used (\(Self.describe(error))).")
            }
        case let .jump(bastion):
            return try await bastion.openRawDirectTCPIP(host: host, port: port) { channel in
                try channel.pipeline.syncOperations.addHandler(SSHBannerGate())
            }
        }
    }

    private static func onEventLoopGroup(
        own: Bool,
        _ connect: (NIOTSEventLoopGroup) async throws -> Channel
    ) async throws -> Channel {
        guard own else { return try await connect(.singleton) }
        let group = NIOTSEventLoopGroup(loopCount: 1)
        do {
            let channel = try await connect(group)
            channel.closeFuture.whenComplete { _ in group.shutdownGracefully { _ in } }
            return channel
        } catch {
            group.shutdownGracefully { _ in }
            throw error
        }
    }

    private static func connectTCP(host: String, port: Int, timeout: TimeAmount, group: NIOTSEventLoopGroup) async throws -> Channel {
        do {
            return try await NIOTSConnectionBootstrap(group: group)
                .connectTimeout(timeout)
                .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(SSHBannerGate())
                    }
                }
                .connect(host: host, port: port)
                .get()
        } catch {
            throw SSHError.connectionFailed("Unable to connect to \(host):\(port) (\(describe(error))).")
        }
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? NWError { return error.debugDescription }
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return String(describing: error)
    }
}
