//
//  SSHKeepalive.swift
//  RayonSSH
//
//  Notices a server that has stopped answering. A connection whose server
//  went to sleep, lost its network or sits behind a NAT that forgot it
//  stays "active" until TCP gives up, which can take hours; until then
//  everything opened on it waits for an answer that never comes.
//
//  When the server has said nothing for an interval, this asks it
//  something that needs a reply; after `limit` unanswered asks in a row
//  the connection is closed, which fails everything waiting on it. TCP
//  keepalive is not enough: a frozen server's kernel still answers it.
//

import NIOCore
@preconcurrency import NIOSSH

final class SSHKeepalive: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = Any

    private let interval: TimeAmount
    private let limit: Int
    private var heard = false
    private var unanswered = 0
    private var timer: Scheduled<Void>?

    init(interval: TimeAmount, limit: Int = 3) {
        self.interval = interval
        self.limit = limit
    }

    func handlerAdded(context: ChannelHandlerContext) {
        schedule(context)
    }

    func handlerRemoved(context _: ChannelHandlerContext) {
        timer?.cancel()
    }

    func channelInactive(context: ChannelHandlerContext) {
        timer?.cancel()
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        heard = true
        context.fireChannelRead(data)
    }

    private func schedule(_ context: ChannelHandlerContext) {
        timer = context.eventLoop.assumeIsolated().scheduleTask(in: interval) { [self] in
            tick(context)
        }
    }

    private func tick(_ context: ChannelHandlerContext) {
        guard context.channel.isActive else { return }
        if heard {
            heard = false
            unanswered = 0
        } else if unanswered >= limit {
            context.close(promise: nil)
            return
        } else {
            unanswered += 1
            ping(context)
        }
        schedule(context)
    }

    /// swift-nio-ssh sends only TCP-forwarding global requests, so the ask
    /// is to cancel a forward that does not exist; servers answer it with a
    /// refusal, which is all the reply needed.
    private func ping(_ context: ChannelHandlerContext) {
        guard let ssh = try? context.pipeline.syncOperations.handler(type: NIOSSHHandler.self) else { return }
        ssh.sendTCPForwardingRequest(.cancel(host: "keepalive@rayon", port: 0), promise: nil)
    }
}
