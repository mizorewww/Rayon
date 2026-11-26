//
//  SSHTransportTests.swift
//  RayonSSHTests
//
//  A connection whose agent may block its event loop gets a loop of its
//  own, over a socket another component connected too.
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
        let channel = try await transport.makeChannel(host: "uu", port: 22, timeout: .seconds(5), ownEventLoop: true)
        let shared = MultiThreadedEventLoopGroup.singleton.makeIterator().contains { $0 === channel.eventLoop }
        XCTAssertFalse(shared, "the socket runs on a shared event loop")
        try await channel.close()
    }
}
