//
//  SOCKS5Handshake.swift
//  RayonSSH
//
//  The server side of a SOCKS5 handshake (RFC 1928), as `ssh -D` speaks
//  it: no authentication, CONNECT only. It reads the client's greeting and
//  request, hands the target over, and answers once the forwarder knows
//  whether the server could reach it.
//
//  Written here rather than taken from swift-nio-extras, whose SOCKS
//  handlers would bring in eleven more packages for these few bytes.
//

import NIOCore

final class SOCKS5Handshake: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundOut = ByteBuffer

    struct Target: Sendable, Equatable {
        var host: String
        var port: Int
    }

    private enum Reply: UInt8 {
        case succeeded = 0x00
        case generalFailure = 0x01
        case hostUnreachable = 0x04
        case commandUnsupported = 0x07
        case addressUnsupported = 0x08
    }

    private enum State {
        case greeting
        case request
        case answering
    }

    private let target: EventLoopPromise<Target>
    private var resolved = false
    private var state = State.greeting
    private var buffered: ByteBuffer?
    private var context: ChannelHandlerContext?

    init(target: EventLoopPromise<Target>) {
        self.target = target
    }

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes = unwrapInboundIn(data)
        if buffered == nil { buffered = bytes } else { buffered!.writeBuffer(&bytes) }
        while var buffer = buffered {
            let progressed: Bool
            switch state {
            case .greeting: progressed = readGreeting(&buffer, context: context)
            case .request: progressed = readRequest(&buffer, context: context)
            case .answering: return
            }
            guard progressed else { return }
            buffered = buffer.readableBytes > 0 ? buffer : nil
        }
    }

    /// VER NMETHODS METHODS…; only "no authentication" (0) is accepted.
    private func readGreeting(_ buffer: inout ByteBuffer, context: ChannelHandlerContext) -> Bool {
        guard let header = buffer.getBytes(at: buffer.readerIndex, length: 2) else { return false }
        guard header[0] == 5 else { return fail(context) }
        guard let methods = buffer.readSlice(length: 2 + Int(header[1]))?.readableBytesView.dropFirst(2) else { return false }
        let accepted = methods.contains(0)
        context.writeAndFlush(wrapOutboundOut(ByteBuffer(bytes: [5, accepted ? 0x00 : 0xFF])), promise: nil)
        guard accepted else { return fail(context) }
        state = .request
        return true
    }

    /// VER CMD RSV ATYP DST.ADDR DST.PORT
    private func readRequest(_ buffer: inout ByteBuffer, context: ChannelHandlerContext) -> Bool {
        let start = buffer.readerIndex
        guard let header = buffer.getBytes(at: start, length: 5) else { return false }
        guard header[0] == 5 else { return fail(context) }
        let addressLength: Int
        switch header[3] {
        case 1: addressLength = 4
        case 3: addressLength = 1 + Int(header[4])
        case 4: addressLength = 16
        default:
            reply(.addressUnsupported)
            return fail(context)
        }
        guard buffer.readableBytes >= 4 + addressLength + 2 else { return false }
        buffer.moveReaderIndex(forwardBy: 4)
        var address = buffer.readSlice(length: addressLength)!
        let port = Int(buffer.readInteger(as: UInt16.self)!)
        guard header[1] == 1 else {
            reply(.commandUnsupported)
            return fail(context)
        }
        let host: String
        switch header[3] {
        case 3:
            address.moveReaderIndex(forwardBy: 1)
            host = address.readString(length: address.readableBytes) ?? ""
        default:
            host = (try? SocketAddress(packedIPAddress: address, port: port).ipAddress) ?? nil ?? ""
        }
        state = .answering
        resolve(.success(Target(host: host, port: port)))
        return true
    }

    /// The target is reached: tells the client to go ahead.
    func accept() {
        reply(.succeeded)
    }

    /// The server could not reach the target.
    func refuse() {
        reply(.hostUnreachable)
        context?.close(promise: nil)
    }

    private func resolve(_ result: Result<Target, Error>) {
        guard !resolved else { return }
        resolved = true
        target.completeWith(result)
    }

    private func reply(_ code: Reply) {
        // The bound address is not meaningful here: 0.0.0.0:0.
        context?.writeAndFlush(wrapOutboundOut(ByteBuffer(bytes: [5, code.rawValue, 0, 1, 0, 0, 0, 0, 0, 0])), promise: nil)
    }

    private func fail(_ context: ChannelHandlerContext) -> Bool {
        state = .answering
        buffered = nil
        resolve(.failure(SSHError.channelRejected("Not a SOCKS5 CONNECT request.")))
        context.close(promise: nil)
        return false
    }

    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        if let buffered, buffered.readableBytes > 0 {
            self.buffered = nil
            context.fireChannelRead(wrapInboundOut(buffered))
        }
        context.leavePipeline(removalToken: removalToken)
    }

    func channelInactive(context: ChannelHandlerContext) {
        resolve(.failure(SSHError.disconnected))
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        resolve(.failure(error))
        context.close(promise: nil)
    }
}
