//
//  VNCInflateStream.swift
//  RayonModule
//
//  ZRLE's zlib stream, inflated with the Compression framework. ZRLE runs
//  one continuous compressed stream across the whole connection — each
//  rectangle feeds the next chunk, sync-flushed — so the decoder state lives
//  as long as the connection. Every chunk's output is capped by the caller,
//  so a crafted frame cannot inflate without bound.
//

import Compression
import Foundation

final class VNCInflateStream {
    enum Failure: Error, Equatable {
        case setup
        case corrupt
        /// The chunk would inflate past the allowed size.
        case outputLimitExceeded(Int)
    }

    private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    /// `COMPRESSION_ZLIB` is raw DEFLATE; the RFC 1950 header the server's
    /// stream opens with is skipped here. There is no trailer to skip: the
    /// stream ends only with the connection.
    private var headerBytesLeft = 2

    init() throws {
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            stream.deallocate()
            throw Failure.setup
        }
    }

    deinit {
        compression_stream_destroy(stream)
        stream.deallocate()
    }

    /// Inflates all of `input` (the next chunk of the stream) and returns
    /// what it decodes to, throwing once that would exceed `maximumOutput`.
    func inflate(_ input: Data, maximumOutput: Int) throws -> Data {
        let skipped = min(headerBytesLeft, input.count)
        headerBytesLeft -= skipped
        let input = input.dropFirst(skipped)
        guard !input.isEmpty else { return Data() }

        // One spare byte tells "exactly at the limit" from "past it".
        var output = Data(count: maximumOutput + 1)
        let produced = try input.withUnsafeBytes { source -> Int in
            try output.withUnsafeMutableBytes { destination -> Int in
                stream.pointee.src_ptr = source.baseAddress!.assumingMemoryBound(to: UInt8.self)
                stream.pointee.src_size = source.count
                stream.pointee.dst_ptr = destination.baseAddress!.assumingMemoryBound(to: UInt8.self)
                stream.pointee.dst_size = destination.count
                // Run until the input is used up and no output is pending,
                // the stream ends, or the cap is hit.
                while stream.pointee.dst_size > 0 {
                    let before = (stream.pointee.src_size, stream.pointee.dst_size)
                    let status = compression_stream_process(stream, 0)
                    guard status != COMPRESSION_STATUS_ERROR else { throw Failure.corrupt }
                    if status == COMPRESSION_STATUS_END { break }
                    if before == (stream.pointee.src_size, stream.pointee.dst_size) {
                        guard stream.pointee.src_size == 0 else { throw Failure.corrupt }
                        break
                    }
                }
                let produced = destination.count - stream.pointee.dst_size
                guard produced <= maximumOutput else { throw Failure.outputLimitExceeded(maximumOutput) }
                return produced
            }
        }
        output.count = produced
        return output
    }
}
