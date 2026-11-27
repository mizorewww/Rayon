//
//  SSHTransportTests.swift
//  RayonSSHTests
//
//  A connection whose agent may block its event loop gets a loop of its
//  own, over a socket another component connected too, and the loop
//  outlives the channel closing.
//

import Foundation
import NIOCore
import NIOPosix
@testable import RayonSSH
import XCTest

final class SSHTransportTests: XCTestCase {
    func testASocketGetsAnEventLoopOfItsOwn() async throws {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let (mine, peer) = (fds[0], fds[1])
        defer { close(peer) }
        let transport = SSHTransport.socket { mine }
        let (channel, ownGroup) = try await transport.makeChannel(host: "uu", port: 22, timeout: .seconds(5), ownEventLoop: true)
        let shared = MultiThreadedEventLoopGroup.singleton.makeIterator().contains { $0 === channel.eventLoop }
        XCTAssertFalse(shared, "the socket runs on a shared event loop")
        XCTAssertNotNil(ownGroup)
        try await channel.close()
        try await ownGroup?.shutdownGracefully()
    }

    /// After the server drops the connection, closing it (as
    /// `SSHConnection.close()` does) and waiting for it to close (as
    /// `closed` and `answers(within:)` do) still finish: the loop is not
    /// shut down under them.
    func testADroppedChannelOnItsOwnLoopStillCloses() async throws {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let (mine, peer) = (fds[0], fds[1])
        let (channel, ownGroup) = try await SSHTransport.socket { mine }
            .makeChannel(host: "uu", port: 22, timeout: .seconds(5), ownEventLoop: true)
        let dropped = expectation(description: "dropped")
        channel.closeFuture.whenComplete { _ in dropped.fulfill() }
        close(peer)
        await fulfillment(of: [dropped], timeout: 3)
        try await Task.sleep(for: .milliseconds(500))

        let done = expectation(description: "close() and closeFuture returned")
        Task.detached {
            try? await channel.close()
            try? await channel.closeFuture.get()
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 3)
        try await ownGroup?.shutdownGracefully()
    }
}

/// What UU Remote hands over: one end of a socket pair, whose other end a
/// tunnel pumps to the server. Signing in and SFTP work across it.
final class SSHSocketTunnelTests: XCTestCase {
    func testSFTPRunsOverASocketPairTunnel() async throws {
        let server = try await TestSSHServer.start(sftp: FixedTreeSFTP(["/home": [("notes.txt", "hello")]]))
        let port = server.port
        let transport = SSHTransport.socket {
            var fds: [Int32] = [0, 0]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw POSIXError(.EIO) }
            let tcp = socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(UInt16(port).bigEndian)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(tcp, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
            Self.pump(from: fds[1], to: tcp)
            Self.pump(from: tcp, to: fds[1])
            return fds[0]
        }
        let connection = try await SSHConnection.connect(.init(
            host: "uu-device", port: 22, username: TestSSHServer.username, credentials: [.password(TestSSHServer.password)],
            transport: transport, timeout: .seconds(15), hostKeyStatus: { _ in .trusted }
        ))
        let sftp = try await connection.openSFTP()
        let entries = try await sftp.entries(at: "/home")
        XCTAssertEqual(entries.map(\.name), ["notes.txt"])
        await sftp.close()
        await connection.close()
        await server.stop()
    }

    private static func pump(from source: Int32, to destination: Int32) {
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(source, $0.baseAddress, $0.count) }
                guard count > 0, buffer.withUnsafeBytes({ write(destination, $0.baseAddress, count) }) == count else { break }
            }
            shutdown(destination, SHUT_WR)
        }
    }
}
