//
//  VNCFramebuffer.swift
//  RayonModule
//
//  The pixel store the RFB decoders write into, and the pictures the stage
//  view shows. Pixels are 32-bit words `0xAARRGGBB`, whose little-endian
//  bytes are B, G, R, A: a `kCVPixelFormatType_32BGRA` pixel buffer's.
//

import CoreGraphics
import CoreVideo
import Foundation
import Synchronization

final class VNCFramebuffer: Sendable {
    /// The widest or tallest desktop accepted: 8K and a little more, a
    /// 256 MiB buffer at most, with a picture or two of the same size on
    /// top. The server names the size, so it is bounded before allocating.
    static let maximumDimension = 8192

    /// The session task draws; the main actor reads the size.
    private let store = Mutex(VNCFramebufferStore())

    var size: CGSize { store.withLock { CGSize(width: $0.width, height: $0.height) } }
    func resize(width: Int, height: Int) { store.withLock { $0.resize(width: width, height: height) } }
    func put(x: Int, y: Int, pixel: UInt32) { store.withLock { $0.put(x: x, y: y, pixel: pixel) } }
    func fill(x: Int, y: Int, width: Int, height: Int, pixel: UInt32) {
        store.withLock { $0.fill(x: x, y: y, width: width, height: height, pixel: pixel) }
    }
    func copy(fromX: Int, fromY: Int, toX: Int, toY: Int, width: Int, height: Int) {
        store.withLock { $0.copy(fromX: fromX, fromY: fromY, toX: toX, toY: toY, width: width, height: height) }
    }
    func putRun(x: Int, y: Int, width: Int, pixels: ArraySlice<UInt32>) {
        store.withLock { $0.putRun(x: x, y: y, width: width, pixels: pixels) }
    }
    func pixel(x: Int, y: Int) -> UInt32? { store.withLock { $0.pixel(x: x, y: y) } }
    func makePicture() -> RemoteDesktopPicture? { store.withLock { $0.makePicture() } }
}

/// The pixels and the pool their pictures come from, behind the
/// framebuffer's Mutex.
private struct VNCFramebufferStore {
    private var pixels: [UInt32] = []
    private(set) var width = 0
    private(set) var height = 0

    /// Resizes the buffer; existing contents are discarded beyond the new
    /// edges and new pixels start transparent-black.
    mutating func resize(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        self.width = width
        self.height = height
        pixels = [UInt32](repeating: 0xFF00_0000, count: width * height)
    }

    /// Writes one canonical pixel.
    mutating func put(x: Int, y: Int, pixel: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = pixel
    }

    /// Fills a rectangle with one canonical pixel, clipped to the buffer.
    mutating func fill(x: Int, y: Int, width w: Int, height h: Int, pixel: UInt32) {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        guard x1 > x0, y1 > y0 else { return }
        let spanCount = x1 - x0
        pixels.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            for row in y0 ..< y1 {
                (base + row * width + x0).initialize(repeating: pixel, count: spanCount)
            }
        }
    }

    /// Copies a rectangle inside the buffer (CopyRect), handling overlapping regions in-place.
    mutating func copy(fromX: Int, fromY: Int, toX: Int, toY: Int, width w: Int, height h: Int) {
        guard w > 0, h > 0 else { return }
        if fromX >= 0, fromY >= 0, toX >= 0, toY >= 0,
           fromX + w <= width, fromY + h <= height,
           toX + w <= width, toY + h <= height
        {
            pixels.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                let rowBytes = w * MemoryLayout<UInt32>.stride
                if toY > fromY {
                    for row in stride(from: h - 1, through: 0, by: -1) {
                        let srcPtr = base + (fromY + row) * width + fromX
                        let dstPtr = base + (toY + row) * width + toX
                        memmove(dstPtr, srcPtr, rowBytes)
                    }
                } else {
                    for row in 0 ..< h {
                        let srcPtr = base + (fromY + row) * width + fromX
                        let dstPtr = base + (toY + row) * width + toX
                        memmove(dstPtr, srcPtr, rowBytes)
                    }
                }
            }
            return
        }

        var source: [UInt32] = []
        source.reserveCapacity(w * h)
        for row in 0 ..< h {
            for column in 0 ..< w {
                let sx = fromX + column, sy = fromY + row
                source.append(
                    (sx >= 0 && sy >= 0 && sx < width && sy < height)
                        ? pixels[sy * width + sx] : 0xFF00_0000
                )
            }
        }
        for row in 0 ..< h {
            for column in 0 ..< w {
                let tx = toX + column, ty = toY + row
                guard tx >= 0, ty >= 0, tx < width, ty < height else { continue }
                pixels[ty * width + tx] = source[row * w + column]
            }
        }
    }

    /// Writes a run of canonical pixels starting at (x, y), wrapping every `w` pixels to the next row.
    mutating func putRun(x: Int, y: Int, width w: Int, pixels line: ArraySlice<UInt32>) {
        guard w > 0, !line.isEmpty else { return }
        let total = line.count
        let rows = (total + w - 1) / w
        pixels.withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress else { return }
            line.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                for row in 0 ..< rows {
                    let py = y + row
                    guard py >= 0, py < height else { continue }
                    let rowStartOffset = row * w
                    let rowLen = min(w, total - rowStartOffset)
                    let colStart = max(0, -x)
                    let colEnd = min(rowLen, width - x)
                    guard colEnd > colStart else { continue }
                    let dstPtr = dstBase + py * width + (x + colStart)
                    let srcPtr = srcBase + rowStartOffset + colStart
                    dstPtr.update(from: srcPtr, count: colEnd - colStart)
                }
            }
        }
    }

    /// Reads one canonical pixel.
    func pixel(x: Int, y: Int) -> UInt32? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return pixels[y * width + x]
    }

    /// The pool the pictures come from, for the framebuffer's size.
    private var pool: CVPixelBufferPool?

    /// The whole framebuffer as a picture: one copy onto a pooled IOSurface,
    /// which then goes to the screen as it is. The copy is what lets the
    /// decoders draw the next update while this one is shown.
    mutating func makePicture() -> RemoteDesktopPicture? {
        guard width > 0, height > 0 else { return nil }
        if pool.map({ Self.matches($0, width: width, height: height) }) != true {
            pool = Self.makePool(width: width, height: height)
        }
        var made: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess,
              let buffer = made, let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue()
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let destinationRow = CVPixelBufferGetBytesPerRow(buffer)
        let sourceRow = width * MemoryLayout<UInt32>.stride
        pixels.withUnsafeBytes { source in
            guard let from = source.baseAddress else { return }
            for row in 0 ..< height {
                (base + row * destinationRow).copyMemory(from: from + row * sourceRow, byteCount: sourceRow)
            }
        }
        return RemoteDesktopPicture(surface: surface)
    }

    private static func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        return pool
    }

    private static func matches(_ pool: CVPixelBufferPool, width: Int, height: Int) -> Bool {
        guard let attributes = CVPixelBufferPoolGetPixelBufferAttributes(pool) as? [CFString: Any] else { return false }
        return attributes[kCVPixelBufferWidthKey] as? Int == width && attributes[kCVPixelBufferHeightKey] as? Int == height
    }
}
