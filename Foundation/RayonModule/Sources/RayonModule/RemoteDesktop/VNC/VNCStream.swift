//
//  VNCStream.swift
//  RayonModule
//
//  The ordered byte stream the RFB client talks over, and the buffered
//  reader the protocol machine pulls exact-length messages from. The TCP
//  transport is `VNCConnection`; tests plug in an in-memory one.
//

import Foundation

/// Bytes to and from the server, in order.
protocol VNCTransport: AnyObject, Sendable {
    /// The next bytes to arrive, at least one and at most `maximumLength`;
    /// throws `endOfStream` once the peer closes.
    func receive(maximumLength: Int) async throws -> Data
    /// Queues `data` behind earlier sends and returns at once: input events
    /// come from the main actor, which must never wait on the network. A
    /// failed send closes the transport, so the next receive reports it.
    func send(_ data: Data)
    /// Closes both directions; a pending receive fails.
    func close()
}

enum VNCStreamError: Error, Equatable {
    case endOfStream
    case failed(String)
}

/// Exact-length reads over a transport, served from a buffer so the many
/// small reads of the decoders do not each wait on the network.
final class VNCReader {
    private let transport: VNCTransport
    /// Received bytes; those before `head` are already consumed.
    private var buffer = Data()
    private var head = 0

    init(_ transport: VNCTransport) {
        self.transport = transport
    }

    /// Reads exactly `count` bytes.
    func read(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        while buffer.count - head < count {
            try Task.checkCancellation()
            // Drop consumed bytes only when more must come anyway, so a run
            // of small reads costs no copying.
            buffer.removeSubrange(0 ..< head)
            head = 0
            buffer.append(try await transport.receive(maximumLength: max(count - buffer.count, 64 * 1024)))
        }
        defer { head += count }
        return buffer.subdata(in: head ..< head + count)
    }
}
