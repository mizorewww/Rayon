//
//  RemoteDesktopFrameViewTests.swift
//  RayonModuleTests
//
//  The canvas's picture view hands surfaces to its display layer.
//

@testable import RayonModule
import AVFoundation
import CoreVideo
import IOSurface
import XCTest

@MainActor
final class RemoteDesktopFrameViewTests: XCTestCase {
    private func picture(width: Int, height: Int) -> RemoteDesktopPicture {
        RemoteDesktopPicture(surface: IOSurface(properties: [.width: width, .height: height, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA])!)
    }

    func testPicturesOfAnySizeGoToTheDisplayLayer() throws {
        let view = RemoteDesktopFrameView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let layer = try XCTUnwrap(view.layer as? AVSampleBufferDisplayLayer)
        XCTAssertEqual(layer.videoGravity, .resize)
        for size in [(4, 4), (4, 4), (8, 2)] {
            let shown = picture(width: size.0, height: size.1)
            view.show(shown)
            XCTAssertTrue(view.picture === shown)
            XCTAssertNotEqual(layer.sampleBufferRenderer.status, .failed)
        }
    }
}
