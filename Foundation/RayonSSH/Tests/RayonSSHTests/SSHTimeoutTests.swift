//
//  SSHTimeoutTests.swift
//  RayonSSHTests
//
//  A server that accepts the connection and then says nothing is given
//  the connection's timeout, and a cancelled connect ends at once.
//

import NIOCore
import NIOPosix
@testable import RayonSSH
import XCTest

final class SSHTimeoutTests: XCTestCase {
    private var silent: Channel!

    override func setUp() async throws {
        silent = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { $0.eventLoop.makeSucceededVoidFuture() }
            .bind(host: "127.0.0.1", port: 0)
            .get()
    }

    override func tearDown() async throws {
        try await silent.close()
    }

    private func connect(_ transport: SSHTransport, timeout: Duration) async throws {
        try await Self.connect(port: silent.localAddress!.port!, transport, timeout: timeout)
    }

    private static func connect(port: Int, _ transport: SSHTransport, timeout: Duration) async throws {
        _ = try await SSHConnection.connect(.init(
            host: "127.0.0.1", port: port, username: "nobody", credentials: [.password("x")],
            transport: transport, timeout: timeout, hostKeyStatus: { _ in .trusted }
        ))
    }

    func testASilentSSHServerTimesOut() async throws {
        let started = ContinuousClock.now
        do {
            try await connect(.tcp, timeout: .seconds(1))
            XCTFail("connected to a silent server")
        } catch let SSHError.connectionFailed(reason) {
            XCTAssertTrue(reason.contains("Timed out"), reason)
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    func testASilentWebSocketServerTimesOut() async throws {
        let endpoint = SSHWebSocketEndpoint(host: "127.0.0.1", port: silent.localAddress!.port!, usesTLS: false)
        let started = ContinuousClock.now
        do {
            try await connect(.webSocket(endpoint), timeout: .seconds(1))
            XCTFail("connected to a silent server")
        } catch let SSHError.connectionFailed(reason) {
            XCTAssertTrue(reason.contains("WebSocket upgrade"), reason)
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    func testCancellingAConnectEndsIt() async throws {
        let port = silent.localAddress!.port!
        for transport in [SSHTransport.tcp, .webSocket(SSHWebSocketEndpoint(host: "127.0.0.1", port: port, usesTLS: false))] {
            let connecting = Task { try await Self.connect(port: port, transport, timeout: .seconds(60)) }
            try await Task.sleep(for: .milliseconds(500))
            let cancelled = ContinuousClock.now
            connecting.cancel()
            do {
                try await connecting.value
                XCTFail("connected to a silent server")
            } catch is CancellationError {}
            XCTAssertLessThan(ContinuousClock.now - cancelled, .seconds(1))
        }
    }
}
