//
//  RemoteDesktopFrameView.swift
//  RayonModule
//
//  The view the canvas shows the remote screen in: its layer is an
//  AVSampleBufferDisplayLayer, which hands each picture's IOSurface to the
//  compositor as it is, BGRA or YUV, scaled on the GPU, with no copy.
//

import AVFoundation
import CoreMedia
import CoreVideo

#if canImport(UIKit)
    import UIKit

    final class RemoteDesktopFrameView: UIView {
        override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
        private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

        /// The picture on screen, nil until the first.
        private(set) var picture: RemoteDesktopPicture?
        private var format: CMVideoFormatDescription?

        override init(frame: CGRect) {
            super.init(frame: frame)
            displayLayer.videoGravity = .resize // it is sized to the fit rect already
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func show(_ picture: RemoteDesktopPicture) {
            self.picture = picture
            displayLayer.show(picture.surface, format: &format)
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class RemoteDesktopFrameView: NSView {
        private let displayLayer = AVSampleBufferDisplayLayer()

        /// The picture on screen, nil until the first.
        private(set) var picture: RemoteDesktopPicture?
        private var format: CMVideoFormatDescription?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            displayLayer.videoGravity = .resize // it is sized to the fit rect already
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func makeBackingLayer() -> CALayer { displayLayer }

        /// Input belongs to the canvas underneath.
        override func hitTest(_: NSPoint) -> NSView? { nil }

        func show(_ picture: RemoteDesktopPicture) {
            self.picture = picture
            displayLayer.show(picture.surface, format: &format)
        }
    }
#endif

private extension AVSampleBufferDisplayLayer {
    /// Enqueues `surface` to be shown at once. `format` is the last
    /// picture's description, made again only when the size or pixel
    /// format changes.
    func show(_ surface: IOSurface, format: inout CMVideoFormatDescription?) {
        var made: Unmanaged<CVPixelBuffer>?
        guard CVPixelBufferCreateWithIOSurface(nil, surface, nil, &made) == kCVReturnSuccess,
              let buffer = made?.takeRetainedValue() else { return }
        if let current = format, CMVideoFormatDescriptionMatchesImageBuffer(current, imageBuffer: buffer) {
            // The same shape as the last picture.
        } else {
            format = nil
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        }
        guard let format,
              let sample = try? CMSampleBuffer(
                  imageBuffer: buffer,
                  formatDescription: format,
                  sampleTiming: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
              ) else { return }
        if var attachments = sample.sampleAttachments.first {
            attachments[.displayImmediately] = true
        }
        let renderer = sampleBufferRenderer
        // A renderer that failed (the app went to the background on iOS)
        // takes pictures again once flushed.
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
        renderer.enqueue(sample)
    }
}
