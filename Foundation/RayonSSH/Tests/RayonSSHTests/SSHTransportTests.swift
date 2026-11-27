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
