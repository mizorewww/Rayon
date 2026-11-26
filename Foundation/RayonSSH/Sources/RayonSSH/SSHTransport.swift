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
    func makeChannel(host: String, port: Int, timeout: TimeAmount) async throws -> Channel {
        switch self {
        case .tcp:
            do {
                return try await NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup.singleton)
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
                throw SSHError.connectionFailed("Unable to connect to \(host):\(port) (\(Self.describe(error))).")
            }
        case let .webSocket(endpoint):
            return try await endpoint.connect(timeout: timeout)
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

    static func describe(_ error: Error) -> String {
        if let error = error as? NWError { return error.debugDescription }
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return String(describing: error)
    }
}
