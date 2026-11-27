//
//  SSHForwardListenerTests.swift
//  RayonSSHTests
//
//  A forward's port is listened on before anything signs in.
//

import NIOCore
import NIOPosix
@testable import RayonSSH
import XCTest

final class SSHForwardListenerTests: XCTestCase {
    func testAPortInUseSaysSo() async throws {
        let taken = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0)
            .get()
        defer { taken.close(promise: nil) }
        let port = try XCTUnwrap(taken.localAddress?.port)
        for listen in [
            { try await SSHForwardListener.local(port: port, targetHost: "127.0.0.1", targetPort: 22) },
            { try await SSHForwardListener.dynamic(port: port) },
        ] {
            do {
                let listener = try await listen()
                await listener.close()
                XCTFail("listened on a port in use")
            } catch let error as SSHError {
                XCTAssertEqual(error, .portInUse(port))
            }
        }
    }
}
