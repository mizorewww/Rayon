//
//  SSHBannerGate.swift
//  RayonSSH
//

import NIOCore

/// Sits where the transport's bytes come out, before the SSH handler is
/// added. The server may speak first, so its bytes wait here until the SSH
/// handler announces itself with its first write; on the way it keeps the
/// server's identification line ("SSH-2.0-OpenSSH_9.6").
final class SSHBannerGate: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var held: [ByteBuffer] = []
    private var open = false
    private var head = ""
    private(set) var serverVersion: String?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = unwrapInboundIn(data)
        if serverVersion == nil { record(bytes) }
        if open {
            context.fireChannelRead(data)
        } else {
            held.append(bytes)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        if open { context.fireChannelReadComplete() }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(data, promise: promise)
        guard !open else { return }
        open = true
        let pending = held
        held = []
        for bytes in pending {
            context.fireChannelRead(wrapInboundOut(bytes))
        }
        if !pending.isEmpty { context.fireChannelReadComplete() }
    }

    private func record(_ bytes: ByteBuffer) {
        guard head.utf8.count < 8192 else { return }
        head += String(buffer: bytes)
        for line in head.split(separator: "\n", omittingEmptySubsequences: false).dropLast() where line.hasPrefix("SSH-") {
            serverVersion = line.trimmingCharacters(in: .whitespacesAndNewlines)
            head = ""
            return
        }
    }
}
