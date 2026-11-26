//
//  SSHByteStream.swift
//  RayonSSH
//
//  A channel read only when asked: each `receive` pulls the next bytes,
//  so a slow reader leaves the SSH window to stop the server.
//

import NIOCore

public struct SSHByteStream: Sendable {
    let channel: Channel

    /// The next bytes, at least one and at most `maximumLength`; throws
    /// `SSHError.disconnected` once the stream ends.
    public func receive(maximumLength: Int) async throws -> ByteBuffer {
        let channel = channel
        return try await channel.eventLoop.flatSubmit {
            do {
                return try channel.pipeline.syncOperations.handler(type: Reader.self).receive(maximumLength: maximumLength)
            } catch {
                return channel.eventLoop.makeFailedFuture(SSHError.disconnected)
            }
        }.get()
    }

    /// Queues `bytes` behind earlier sends and returns at once.
    public func send(_ bytes: ByteBuffer) {
        let channel = channel
        channel.writeAndFlush(bytes).whenFailure { _ in channel.close(promise: nil) }
    }

    public func close() {
        channel.close(promise: nil)
    }

    final class Reader: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer

        private var context: ChannelHandlerContext?
        private var buffered: ByteBuffer?
        private var waiting: (promise: EventLoopPromise<ByteBuffer>, limit: Int)?
        private var ended = false

        func handlerAdded(context: ChannelHandlerContext) {
            self.context = context
        }

        func receive(maximumLength: Int) -> EventLoopFuture<ByteBuffer> {
            guard let context else { return failed() }
            let promise = context.eventLoop.makePromise(of: ByteBuffer.self)
            waiting = (promise, max(1, maximumLength))
            deliver()
            if waiting != nil {
                if ended { waiting = nil; promise.fail(SSHError.disconnected) } else { context.read() }
            }
            return promise.futureResult
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var bytes = unwrapInboundIn(data)
            if buffered == nil { buffered = bytes } else { buffered!.writeBuffer(&bytes) }
            deliver()
        }

        func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            if let event = event as? ChannelEvent, event == .inputClosed { end() }
            context.fireUserInboundEventTriggered(event)
        }

        func channelInactive(context: ChannelHandlerContext) {
            end()
            context.fireChannelInactive()
        }

        private func end() {
            ended = true
            if buffered == nil, let waiting {
                self.waiting = nil
                waiting.promise.fail(SSHError.disconnected)
            }
        }

        private func deliver() {
            guard let waiting, var bytes = buffered, bytes.readableBytes > 0 else { return }
            let chunk = bytes.readSlice(length: min(waiting.limit, bytes.readableBytes))!
            buffered = bytes.readableBytes > 0 ? bytes : nil
            self.waiting = nil
            waiting.promise.succeed(chunk)
        }

        private func failed() -> EventLoopFuture<ByteBuffer> {
            context?.eventLoop.makeFailedFuture(SSHError.disconnected) ?? preconditionFailureFuture()
        }

        private func preconditionFailureFuture() -> EventLoopFuture<ByteBuffer> {
            preconditionFailure("receive called before the reader joined a pipeline")
        }
    }
}
