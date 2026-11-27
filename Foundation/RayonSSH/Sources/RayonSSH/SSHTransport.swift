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
import NIOSSH
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
    /// With `ownEventLoop`, the connection runs on an event loop of its
    /// own, returned to be shut down by whoever owns the channel once
    /// nothing uses it any more: a loop shut down when the channel closes
    /// would leave every later `close()` or wait on the channel hanging.
    /// Blocking that loop holds no other connection. A jump's channel
    /// cannot have one: it is a child of the bastion's and runs on its
    /// loop, so an agent asking the person to confirm still holds whatever
    /// else shares that loop until the agent answers.
    func makeChannel(
        host: String,
        port: Int,
        timeout: TimeAmount,
        ownEventLoop: Bool = false
    ) async throws -> (channel: Channel, ownGroup: EventLoopGroup?) {
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
            let own = ownEventLoop ? MultiThreadedEventLoopGroup(numberOfThreads: 1) : nil
            do {
                let channel = try await ClientBootstrap(group: own ?? MultiThreadedEventLoopGroup.singleton)
                    .channelInitializer { channel in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(SSHBannerGate())
                        }
                    }
                    .withConnectedSocket(descriptor)
                    .get()
                return (channel, own)
            } catch {
                own?.shutdownGracefully { _ in }
                close(descriptor)
                throw SSHError.connectionFailed("The tunnel to \(host):\(port) could not be used (\(Self.describe(error))).")
            }
        case let .jump(bastion):
            let channel = try await bastion.openRawDirectTCPIP(host: host, port: port) { channel in
                try channel.pipeline.syncOperations.addHandler(SSHBannerGate())
            }
            return (channel, nil)
        }
    }

    /// Opens the stream to the server and closes it again, signing in to
    /// nothing: whether the server can be reached at all. A jump host is
    /// given over and closed, as `SSHConnection.connect` does.
    public func reach(host: String, port: Int, timeout: Duration) async throws {
        defer { if case let .jump(bastion) = self { Task { await bastion.close() } } }
        let (channel, _) = try await makeChannel(host: host, port: port, timeout: TimeAmount(timeout))
        try? await channel.close()
    }

    private static func onEventLoopGroup(
        own: Bool,
        _ connect: (NIOTSEventLoopGroup) async throws -> Channel
    ) async throws -> (channel: Channel, ownGroup: EventLoopGroup?) {
        guard own else { return try await (connect(.singleton), nil) }
        let group = NIOTSEventLoopGroup(loopCount: 1)
        do {
            return try await (connect(group), group)
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

    /// What went wrong under SSH, worded for the person: the one mapping of
    /// Network.framework, NIO, POSIX and SSH protocol errors, which would
    /// otherwise show as "POSIXErrorCode(rawValue: 61): Connection refused"
    /// or "NIOSSH.NIOSSHError error 1".
    public static func describe(_ error: Error) -> String {
        switch error {
        case let error as NWError:
            switch error {
            case let .posix(code): return describe(code)
            case .dns: return "the host name could not be found"
            case let .tls(status): return "TLS failed: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)")
            default: return error.localizedDescription
            }
        case let error as IOError:
            return POSIXErrorCode(rawValue: error.errnoCode).map(describe) ?? error.description
        case let error as POSIXError:
            return describe(error.code)
        case ChannelError.connectTimeout:
            return "the server did not answer in time"
        case ChannelError.ioOnClosedChannel, ChannelError.alreadyClosed, ChannelError.eof, ChannelError.outputClosed, ChannelError.inputClosed:
            return "the connection closed"
        case let error as NIOSSHError:
            return "the SSH session broke off (\(error.type))"
        case let error as LocalizedError where error.errorDescription != nil:
            return error.errorDescription ?? ""
        default:
            return String(describing: error)
        }
    }

    static func describe(_ code: POSIXErrorCode) -> String {
        switch code {
        case .ECONNREFUSED: "connection refused; nothing is listening on that port"
        case .ETIMEDOUT: "the server did not answer in time"
        case .EHOSTUNREACH, .EHOSTDOWN: "the host cannot be reached"
        case .ENETUNREACH: "the network cannot reach the host"
        case .ENETDOWN: "the network is down"
        case .ECONNRESET: "the server reset the connection"
        case .ECONNABORTED: "the connection was aborted"
        case .EPIPE, .ENOTCONN: "the connection closed"
        case .EADDRINUSE: "the port is already in use"
        case .EACCES, .EPERM: "the system did not allow the connection"
        default: String(cString: strerror(code.rawValue))
        }
    }
}
