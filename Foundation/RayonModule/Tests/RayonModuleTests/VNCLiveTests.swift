//
//  VNCLiveTests.swift
//  RayonModuleTests
//
//  Against a real VNC server; skipped unless VNC_LIVE_PORT is set (host
//  VNC_LIVE_HOST, default 127.0.0.1; VNC_LIVE_PASSWORD if it asks for one).
//  A throwaway server: an Alpine container running Xvfb + x11vnc, e.g.
//  `docker run --rm -d -p 5900:5900 -e VNC_PASSWORD=secret <image>`.
//

@testable import RayonModule
import CoreGraphics
import XCTest

final class VNCLiveTests: XCTestCase {
    private final class Recorder: VNCRFBClientDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var phases: [RemoteDesktopPhase] = []
        private var frames = 0
        private var lastImage: CGImage?
        let connected = XCTestExpectation(description: "connected")
        let framed = XCTestExpectation(description: "a decoded frame")
        let ended = XCTestExpectation(description: "failed or closed")

        func client(_: VNCRFBClient, didChangePhase phase: RemoteDesktopPhase, hint _: String?) {
            lock.withLock { phases.append(phase) }
            switch phase {
            case .connected: connected.fulfill()
            case .failed, .closed: ended.fulfill()
            default: break
            }
        }

        func client(_: VNCRFBClient, didUpdateFrame image: CGImage?, size _: CGSize, desktopName _: String?) {
            guard let image else { return }
            let first = lock.withLock { () -> Bool in
                frames += 1
                lastImage = image
                return frames == 1
            }
            if first { framed.fulfill() }
        }

        func client(_: VNCRFBClient, didUpdateCursor _: RemoteCursorInfo?) {}
        func client(_: VNCRFBClient, didReceiveClipboard _: String) {}

        var failure: String? {
            lock.withLock {
                phases.lazy.compactMap { phase -> String? in
                    if case let .failed(reason) = phase { return reason }
                    return nil
                }.first
            }
        }

        var image: CGImage? { lock.withLock { lastImage } }
    }

    private func server() throws -> (host: String, port: UInt16, password: String) {
        let environment = ProcessInfo.processInfo.environment
        guard let port = environment["VNC_LIVE_PORT"].flatMap(UInt16.init) else {
            throw XCTSkip("Set VNC_LIVE_PORT to run the live VNC tests")
        }
        return (environment["VNC_LIVE_HOST"] ?? "127.0.0.1", port, environment["VNC_LIVE_PASSWORD"] ?? "")
    }

    /// Connects over Network.framework, authenticates, and decodes real
    /// frames (x11vnc answers with ZRLE); input goes out while it runs.
    func testConnectsAndDecodesFrames() async throws {
        let server = try server()
        let recorder = Recorder()
        let client = VNCRFBClient(
            configuration: .init(host: server.host, port: server.port, password: server.password, shared: true),
            delegate: recorder
        )
        client.start()
        await fulfillment(of: [recorder.connected, recorder.framed], timeout: 15)
        XCTAssertNil(recorder.failure)
        let image = try XCTUnwrap(recorder.image)
        XCTAssertGreaterThan(image.width, 0)

        client.pointerMoved(normalizedX: 0.5, normalizedY: 0.5)
        client.keyEvent(keyCode: 0, keySym: 0x61, characters: "a", isDown: true)
        client.keyEvent(keyCode: 0, keySym: 0x61, characters: "a", isDown: false)
        client.requestUpdate(incremental: false)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(recorder.failure)
        client.stop()
    }

    /// A password set for a server that offers no authentication is a
    /// downgrade: the client must refuse rather than walk in.
    func testRefusesNoAuthServerWhenPasswordIsSet() async throws {
        let server = try server()
        guard server.password.isEmpty else {
            throw XCTSkip("Needs a server without a password (VNC_LIVE_PASSWORD unset)")
        }
        let recorder = Recorder()
        let client = VNCRFBClient(
            configuration: .init(host: server.host, port: server.port, password: "configured", shared: true),
            delegate: recorder
        )
        client.start()
        await fulfillment(of: [recorder.ended], timeout: 15)
        XCTAssertTrue(recorder.failure?.contains("without authentication") == true, recorder.failure ?? "no failure")
        client.stop()
    }

    func testWrongPasswordIsRejected() async throws {
        let server = try server()
        guard !server.password.isEmpty else {
            throw XCTSkip("Needs a server with a password (VNC_LIVE_PASSWORD)")
        }
        let recorder = Recorder()
        let client = VNCRFBClient(
            configuration: .init(host: server.host, port: server.port, password: server.password + "x", shared: true),
            delegate: recorder
        )
        client.start()
        await fulfillment(of: [recorder.ended], timeout: 15)
        XCTAssertNotNil(recorder.failure)
        client.stop()
    }
}
