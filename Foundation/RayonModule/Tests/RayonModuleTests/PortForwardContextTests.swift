//
//  PortForwardContextTests.swift
//  RayonModuleTests
//
//  A forward whose local port is taken says so, and keeps saying so while
//  it retries, and signs in to nothing.
//

import NIOCore
import NIOPosix
import os
@testable import RayonModule
import XCTest

final class PortForwardContextTests: XCTestCase {
    /// It used to sign in, fail to listen, and sign in again every three
    /// seconds for as long as the port stayed taken.
    @MainActor
    func testAForwardOnAPortInUseDoesNotSignIn() async throws {
        let signIns = OSAllocatedUnfairLock(initialState: 0)
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                signIns.withLock { $0 += 1 }
                return channel.close()
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        defer { server.close(promise: nil) }
        let taken = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0)
            .get()
        defer { taken.close(promise: nil) }

        let test = try TestStorage()
        let store = test.store()
        store.publishesWorkerSnapshot = true
        defer { RayonStore.workerSnapshot.withLock { $0 = WorkerSnapshot() } }
        let identity = RDIdentity(username: "nobody", password: "pw")
        store.save(identity)
        let machine = RDMachine(remoteAddress: "127.0.0.1", remotePort: "\(server.localAddress!.port!)", name: "server", associatedIdentity: identity.id)
        store.save(machine)

        let forward = RDPortForward(
            forwardOrientation: .listenLocal, bindPort: taken.localAddress!.port!,
            targetHost: "127.0.0.1", targetPort: 80, usingMachine: machine.id
        )
        let context = PortForwardContext(info: forward, machine: machine)
        context.reconnectDelay = 0.2
        let states = OSAllocatedUnfairLock<[PortForwardContext.Lifecycle]>(initialState: [])
        context.lifecycleHandler = { state in states.withLock { $0.append(state) } }
        context.begin()
        try await Task.sleep(for: .seconds(1.5))
        context.terminate()

        XCTAssertEqual(signIns.withLock { $0 }, 0, "signed in for a forward that cannot listen")
        // Retrying the listen does not flip it to awaiting connect between.
        let seen = states.withLock { $0 }
        XCTAssertGreaterThan(seen.count, 1, "\(seen)")
        XCTAssertTrue(seen.allSatisfy { $0 == .portInUse }, "\(seen)")
    }
}
