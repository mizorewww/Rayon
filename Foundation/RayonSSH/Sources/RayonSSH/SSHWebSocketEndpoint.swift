//
//  SSHWebSocketEndpoint.swift
//  RayonSSH
//
//  What `cloudflared access ssh` does without cloudflared, which a
//  sandboxed app cannot run: a WebSocket to the host, whose binary
//  messages Cloudflare's edge relays to the SSH server behind a Cloudflare
//  Tunnel. NIO speaks the WebSocket; the SSH session runs on top of it in
//  the same pipeline.
//

import Foundation
import Network
import NIOCore
import NIOHTTP1
import NIOTransportServices
import NIOWebSocket

public struct SSHWebSocketEndpoint: Sendable {
    public var host: String
    public var port: Int
    public var path: String
    public var usesTLS: Bool
    /// Extra request headers, Cloudflare Access service-token ones for one.
    public var headers: [(String, String)]

    public init(host: String, port: Int = 443, path: String = "/", usesTLS: Bool = true, headers: [(String, String)] = []) {
        self.host = host
        self.port = port
        self.path = path
        self.usesTLS = usesTLS
        self.headers = headers
    }

    /// The server answered with HTTP instead of switching to WebSocket.
    public struct Refusal: Error, Sendable {
        public let status: Int
        public let location: String?
    }

    func connect(timeout: TimeAmount, group: NIOTSEventLoopGroup = .singleton) async throws -> Channel {
        let eventLoop = group.next()
        let upgraded = eventLoop.makePromise(of: Void.self)
        guard var bootstrap = NIOTSConnectionBootstrap(validatingGroup: eventLoop) else {
            throw SSHError.connectionFailed("No event loop for the WebSocket to \(host).", cause: .other)
        }
        bootstrap = bootstrap
            .connectTimeout(timeout)
            .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
        if usesTLS { bootstrap = bootstrap.tlsOptions(NWProtocolTLS.Options()) }
        let request = makeRequest()
        let channel: Channel
        do {
            channel = try await bootstrap.channelInitializer { channel in
                let upgrader = NIOWebSocketClientUpgrader(maxFrameSize: 1 << 22) { channel, _ in
                    channel.eventLoop.makeCompletedFuture {
                        let sync = channel.pipeline.syncOperations
                        sync.removeHandler(try sync.handler(type: WebSocketUpgradeRequester.self)).whenComplete { _ in }
                        try sync.addHandlers(WebSocketByteStream(), SSHBannerGate())
                        upgraded.succeed()
                    }
                }
                return channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    try sync.addHTTPClientHandlers(withClientUpgrade: (upgraders: [upgrader], completionHandler: { _ in }))
                    try sync.addHandler(WebSocketUpgradeRequester(request: request, upgraded: upgraded))
                }
            }
            .connect(host: host, port: port)
            .get()
        } catch {
            upgraded.fail(error)
            throw SSHError.connectionFailed("Unable to reach \(host) (\(SSHTransport.describe(error))).", cause: SSHTransport.cause(of: error))
        }
        // A server that accepts the connection but never answers the
        // upgrade is given the connect timeout, and a cancelled task ends it.
        let deadline = channel.eventLoop.scheduleTask(in: timeout) {
            upgraded.fail(SSHError.connectionFailed("\(host) did not answer the WebSocket upgrade in time.", cause: .timedOut))
        }
        defer { deadline.cancel() }
        do {
            try await withTaskCancellationHandler {
                try await upgraded.futureResult.get()
            } onCancel: {
                upgraded.fail(CancellationError())
            }
        } catch {
            channel.close(promise: nil)
            throw error
        }
        return channel
    }

    private func makeRequest() -> HTTPRequestHead {
        var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: path)
        head.headers.add(name: "Host", value: host)
        head.headers.add(name: "Content-Length", value: "0")
        for (name, value) in headers {
            head.headers.add(name: name, value: value)
        }
        return head
    }
}

/// Sends the upgrade request once the connection is up, and fails the
/// upgrade with the HTTP status when the server answers without switching.
private final class WebSocketUpgradeRequester: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let request: HTTPRequestHead
    private let upgraded: EventLoopPromise<Void>

    init(request: HTTPRequestHead, upgraded: EventLoopPromise<Void>) {
        self.request = request
        self.upgraded = upgraded
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive { send(context: context) }
    }

    func channelActive(context: ChannelHandlerContext) {
        send(context: context)
        context.fireChannelActive()
    }

    private func send(context: ChannelHandlerContext) {
        context.write(wrapOutboundOut(.head(request)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case let .head(response) = unwrapInboundIn(data) else { return }
        upgraded.fail(SSHWebSocketEndpoint.Refusal(status: Int(response.status.code), location: response.headers.first(name: "Location")))
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        upgraded.fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        upgraded.fail(SSHError.disconnected)
        context.fireChannelInactive()
    }
}

/// WebSocket frames to bytes and back; every write is one binary message.
private final class WebSocketByteStream: ChannelDuplexHandler {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .binary, .text, .continuation:
            context.fireChannelRead(wrapInboundOut(frame.unmaskedData))
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            context.close(promise: nil)
        default:
            break
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let frame = WebSocketFrame(fin: true, opcode: .binary, maskKey: .random(), data: unwrapOutboundIn(data))
        context.write(wrapOutboundOut(frame), promise: promise)
    }
}
