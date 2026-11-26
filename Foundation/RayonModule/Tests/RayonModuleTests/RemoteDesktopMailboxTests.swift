//
//  RemoteDesktopMailboxTests.swift
//  RayonModuleTests
//
//  Frames and cursors from a driver's threads, on their way to the canvas.
//

@testable import RayonModule
import CoreGraphics
import CoreVideo
import IOSurface
import XCTest

final class RemoteDesktopMailboxTests: XCTestCase {
    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    func testFramesWaitingForTheMainActorCollapseToTheLatest() {
        let mailbox = RemoteDesktopMailbox()
        let first = image()
        let latest = image()
        XCTAssertTrue(mailbox.post(frame: .image(first), size: CGSize(width: 2, height: 2), desktopName: "host"))
        XCTAssertFalse(mailbox.post(frame: .image(latest), size: CGSize(width: 2, height: 2), desktopName: nil))
        // A size change without a picture keeps the waiting picture.
        XCTAssertFalse(mailbox.post(frame: nil, size: CGSize(width: 4, height: 4), desktopName: nil))
        XCTAssertFalse(mailbox.post(cursor: nil))
        let mail = mailbox.take()
        guard case let .image(taken) = mail.frame?.picture else { return XCTFail("no picture") }
        XCTAssertTrue(taken === latest)
        XCTAssertEqual(mail.frame?.size, CGSize(width: 4, height: 4))
        XCTAssertEqual(mail.frame?.desktopName, "host")
        XCTAssertNotNil(mail.cursor, "a hidden cursor is news too")
        XCTAssertEqual(mailbox.takeFrameCount(), 2)
        // Taken: the next post asks for a trip again.
        XCTAssertTrue(mailbox.post(cursor: nil))
        XCTAssertNil(mailbox.take().frame)
    }

    /// A decoded frame goes to the layer as its IOSurface, not converted.
    func testAPixelBufferIsShownAsItsIOSurface() throws {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, attributes, &buffer), kCVReturnSuccess)
        let contents = try XCTUnwrap(RemoteDesktopPicture.pixelBuffer(XCTUnwrap(buffer)).layerContents)
        XCTAssertTrue((contents as AnyObject) === CVPixelBufferGetIOSurface(buffer!)?.takeUnretainedValue())
    }
}
