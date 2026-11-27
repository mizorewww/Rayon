//
//  VNCLiveTests.swift
//  RayonModuleTests
//
//  Against a real VNC server; skipped unless VNC_LIVE_PORT is set (host
//  VNC_LIVE_HOST, default 127.0.0.1; VNC_LIVE_PASSWORD if it asks for one).
//  A throwaway server: an Alpine container running Xvfb + x11vnc, e.g.
//  `docker run --rm -d -p 5900:5900 -e VNC_PASSWORD=secret <image>`.
//  VNC_LIVE_SNAPSHOT=<path.png> saves the latest decoded frame.
//  The SSH test also wants VNC_LIVE_SSH_PORT / _USER / _PASSWORD: an sshd
//  in the same container, forwarding to the VNC server's loopback port.
//

@testable import RayonModule
import CoreGraphics
import CoreImage
import ImageIO
import RayonSSH
import Synchronization
import XCTest

final class VNCLiveTests: XCTestCase {
    private final class Recorder: VNCRFBClientDelegate {
        private struct Record {
            var phases: [RemoteDesktopPhase] = []
            var frames = 0
            var lastPicture: RemoteDesktopPicture?
        }

        private let record = Mutex(Record())
        let connected = XCTestExpectation(description: "connected")
        let framed = XCTestExpectation(description: "a decoded frame")
        let ended = XCTestExpectation(description: "failed or closed")

        func client(_: VNCRFBClient, didChangePhase phase: RemoteDesktopPhase, hint _: String?) {
            record.withLock { $0.phases.append(phase) }
            switch phase {
            case .connected: connected.fulfill()
            case .failed, .closed: ended.fulfill()
            default: break
            }
        }

        func client(_: VNCRFBClient, didUpdateFrame picture: RemoteDesktopPicture?, size _: CGSize, desktopName _: String?) {
            guard let picture else { return }
            let first = record.withLock { record in
                record.frames += 1
                record.lastPicture = picture
                return record.frames == 1
            }
            if first { framed.fulfill() }
        }

        func client(_: VNCRFBClient, didUpdateCursor _: RemoteCursorInfo?) {}
        func client(_: VNCRFBClient, didReceiveClipboard _: String) {}

        var failure: String? {
            record.withLock {
                $0.phases.lazy.compactMap { phase -> String? in
                    if case let .failed(reason) = phase { return reason }
                    return nil
                }.first
            }
        }

        var picture: RemoteDesktopPicture? { record.withLock { $0.lastPicture } }
        var frameCount: Int { record.withLock { $0.frames } }
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
        let picture = try XCTUnwrap(recorder.picture)
        XCTAssertGreaterThan(picture.surface.width, 0)

        // Changing content, not only the first frame: ZRLE runs one zlib
        // stream across every rectangle, so later updates are where a
        // decoder that loses stream state breaks. Moving the pointer and
        // opening and closing a menu repaints parts of a real desktop.
        let before = recorder.frameCount
        for step in 0 ..< 20 {
            let x = 0.1 + 0.8 * Double(step % 5) / 4, y = 0.1 + 0.8 * Double(step / 5) / 3
            client.pointerMoved(normalizedX: x, normalizedY: y)
            if step % 5 == 2 {
                client.pointerButton(.right, isDown: true, normalizedX: x, normalizedY: y)
                client.pointerButton(.right, isDown: false, normalizedX: x, normalizedY: y)
            }
            if step % 5 == 4 {
                client.keyEvent(keyCode: 0, keySym: 0xFF1B, characters: "", isDown: true)
                client.keyEvent(keyCode: 0, keySym: 0xFF1B, characters: "", isDown: false)
                client.requestUpdate(incremental: false)
            }
            try await Task.sleep(for: .milliseconds(200))
            if let failure = recorder.failure {
                return XCTFail("\(failure) after \(recorder.frameCount - before) more frames")
            }
        }
        XCTAssertGreaterThan(recorder.frameCount - before, 3, "updates stopped arriving")
        // VNC_LIVE_SNAPSHOT=<path.png> keeps the latest decoded frame to look at.
        if let path = ProcessInfo.processInfo.environment["VNC_LIVE_SNAPSHOT"],
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) {
            let surface = try XCTUnwrap(recorder.picture).surface
            let image = try XCTUnwrap(CIContext().createCGImage(CIImage(ioSurface: surface), from: CGRect(x: 0, y: 0, width: surface.width, height: surface.height)))
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
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

    /// `vncOverSSH`: the client runs over a direct-tcpip channel — no local
    /// listening port involved.
    func testConnectsOverSSHDirectTCPIP() async throws {
        let server = try server()
        let environment = ProcessInfo.processInfo.environment
        guard let sshPort = environment["VNC_LIVE_SSH_PORT"],
              let user = environment["VNC_LIVE_SSH_USER"],
              let password = environment["VNC_LIVE_SSH_PASSWORD"]
        else {
            throw XCTSkip("Set VNC_LIVE_SSH_PORT, _USER and _PASSWORD to run the VNC-over-SSH test")
        }
        let connection = try await SSHConnection.connect(.init(
            host: server.host,
            port: Int(sshPort) ?? 22,
            username: user,
            credentials: [.password(password)],
            timeout: .seconds(10),
            hostKeyStatus: { _ in .trusted }
        ))
        let lease = SSHLease(connection: connection, identity: RDIdentity()) { await connection.close() }
        let stream = try await connection.openByteStream(host: "127.0.0.1", port: 5900)

        let recorder = Recorder()
        let client = VNCRFBClient(
            configuration: .init(host: server.host, port: 0, password: server.password, shared: true,
                                 transport: SSHChannelTransport(stream: stream, lease: lease)),
            delegate: recorder
        )
        client.start()
        await fulfillment(of: [recorder.connected, recorder.framed], timeout: 15)
        XCTAssertNil(recorder.failure)
        // Full refreshes of a noisy desktop are several MB each and must
        // keep flowing through the channel (the old 8 KB socket pair tore
        // the tunnel down on the first one).
        let surface = try XCTUnwrap(recorder.picture).surface
        XCTAssertGreaterThan(surface.width * surface.height * 4, 2 * 1024 * 1024, "use a desktop of at least 1024x512")
        let before = recorder.frameCount
        for _ in 0 ..< 5 {
            client.requestUpdate(incremental: false)
            try await Task.sleep(for: .milliseconds(500))
        }
        try await Task.sleep(for: .seconds(2))
        XCTAssertNil(recorder.failure)
        XCTAssertGreaterThanOrEqual(recorder.frameCount - before, 3, "full frames stopped arriving")
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
