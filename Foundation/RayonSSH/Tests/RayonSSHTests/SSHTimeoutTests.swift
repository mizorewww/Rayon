//
//  SSHTimeoutTests.swift
//  RayonSSHTests
//
//  A server that accepts the connection and then says nothing is given
//  the connection's timeout, one slow to sign in is given all of it, and a
//  cancelled connect ends at once. Citadel's sign-in ends when its
//  channel closes, even with no login timeout.
//

@preconcurrency import Citadel
import NIOCore
import NIOPosix
import os
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

    /// Citadel gave up on signing in after a fixed 10 seconds, whatever
    /// the connection's timeout: a slow server, or an agent waiting for
    /// Touch ID, read as one out of reach.
    func testSigningInMayTakeAsLongAsTheTimeout() async throws {
        let server = try await TestSSHServer.start(signInDelay: .seconds(11))
        let started = ContinuousClock.now
        let connection = try await server.connect(timeout: .seconds(30))
        XCTAssertGreaterThan(ContinuousClock.now - started, .seconds(10))
        await connection.close()
        await server.stop()
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

    /// Rayon turns Citadel's login timeout off and keeps its own deadline,
    /// so an abandoned sign-in whose channel closed must still end, or its
    /// task and handshake state stay alive.
    func testCitadelsSignInEndsWhenItsChannelClosesWithoutALoginTimeout() async throws {
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connect(host: "127.0.0.1", port: silent.localAddress!.port!).get()
        var settings = SSHClientSettings(
            host: "127.0.0.1", port: 22,
            authenticationMethod: { .passwordBased(username: "u", password: "p") },
            hostKeyValidator: .acceptAnything()
        )
        settings.loginTimeout = nil
        let ended = OSAllocatedUnfairLock(initialState: false)
        let signingIn = Task { [settings] in
            _ = try? await withTaskExecutorPreference(EventLoopTaskExecutor(channel.eventLoop)) {
                try await SSHClient.connect(on: channel, settings: settings)
            }
            ended.withLock { $0 = true }
        }
        try await Task.sleep(for: .milliseconds(300))
        try await channel.close()
        try await Task.sleep(for: .seconds(2))
        signingIn.cancel()
        XCTAssertTrue(ended.withLock { $0 }, "Citadel kept waiting to sign in on a closed channel")
    }
}
