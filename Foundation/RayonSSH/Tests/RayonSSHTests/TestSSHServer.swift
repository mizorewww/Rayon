//
//  TestSSHServer.swift
//  RayonSSHTests
//
//  An SSH server in the test process (Citadel's), for what OpenSSH in
//  the Docker container will not do: take its time signing in, or list
//  names no file system holds.
//

@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
@testable import RayonSSH

final class TestSSHServer {
    static let username = "rayon"
    static let password = "test"

    let port: Int
    private let server: SSHServer
    private let group: MultiThreadedEventLoopGroup

    private init(port: Int, server: SSHServer, group: MultiThreadedEventLoopGroup) {
        self.port = port
        self.server = server
        self.group = group
    }

    /// Accepts the password after `signInDelay`, and serves SFTP through
    /// `sftp` when given.
    static func start(signInDelay: TimeAmount = .zero, sftp: (any SFTPDelegate)? = nil) async throws -> TestSSHServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let port = try freePort()
        let server = try await SSHServer.host(
            host: "127.0.0.1",
            port: port,
            hostKeys: [NIOSSHPrivateKey(ed25519Key: .init())],
            authenticationDelegate: PasswordDelegate(delay: signInDelay),
            group: group
        )
        if let sftp { server.enableSFTP(withDelegate: sftp) }
        return TestSSHServer(port: port, server: server, group: group)
    }

    func connect(timeout: Duration = .seconds(15)) async throws -> SSHConnection {
        try await SSHConnection.connect(.init(
            host: "127.0.0.1", port: port, username: Self.username, credentials: [.password(Self.password)],
            timeout: timeout, hostKeyStatus: { _ in .trusted }
        ))
    }

    func stop() async {
        try? await server.close()
        try? await group.shutdownGracefully()
    }

    private static func freePort() throws -> Int {
        let socket = try ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).bind(host: "127.0.0.1", port: 0).wait()
        defer { try? socket.close().wait() }
        return socket.localAddress?.port ?? 0
    }
}

private final class PasswordDelegate: NIOSSHServerUserAuthenticationDelegate {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = .password
    let delay: TimeAmount

    init(delay: TimeAmount) { self.delay = delay }

    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        guard case let .password(password) = request.request,
              request.username == TestSSHServer.username, password.password == TestSSHServer.password
        else { return responsePromise.succeed(.failure) }
        responsePromise.futureResult.eventLoop.scheduleTask(in: delay) { responsePromise.succeed(.success) }
    }
}
