//
//  SSHChannelHandlers.swift
//  RayonSSH
//
//  Turn SSH child channels into plain streams for NIOAsyncChannel, which
//  carries the backpressure: it stops reading when its buffer is full, and
//  the SSH window stops the server in turn.
//

import NIOCore
import NIOSSH

/// A child channel's data as bytes, both ways.
final class SSHChannelByteCodec: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .channel = message.type, case let .byteBuffer(bytes) = message.data else { return }
        context.fireChannelRead(wrapInboundOut(bytes))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let bytes = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(bytes))), promise: promise)
    }
}

/// What a session channel (a shell or a command) reports.
public enum SSHSessionEvent: Sendable {
    case output(ByteBuffer)
    case errorOutput(ByteBuffer)
    /// The server answered a request that asked for a reply.
    case requestAccepted
    case requestRejected
    case exitStatus(Int32)
    case exitSignal(String)
}

/// A session channel's data and its in-band events as one stream.
final class SSHSessionHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = SSHSessionEvent
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case let .byteBuffer(bytes) = message.data else { return }
        switch message.type {
        case .channel: context.fireChannelRead(wrapInboundOut(.output(bytes)))
        case .stdErr: context.fireChannelRead(wrapInboundOut(.errorOutput(bytes)))
        default: break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            context.fireChannelRead(wrapInboundOut(.requestAccepted))
        case is ChannelFailureEvent:
            context.fireChannelRead(wrapInboundOut(.requestRejected))
        case let status as SSHChannelRequestEvent.ExitStatus:
            context.fireChannelRead(wrapInboundOut(.exitStatus(Int32(truncatingIfNeeded: status.exitStatus))))
        case let signal as SSHChannelRequestEvent.ExitSignal:
            context.fireChannelRead(wrapInboundOut(.exitSignal(signal.signalName)))
        case ChannelEvent.inputClosed:
            // The exit status may follow the server's EOF; the stream ends
            // when the channel closes.
            break
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let bytes = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(bytes))), promise: promise)
    }
}
