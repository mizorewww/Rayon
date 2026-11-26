//
//  VNCSocketPairTransportTests.swift
//  RayonModuleTests
//
//  The `vncOverSSH` transport over a plain socketpair, standing in for the
//  SSH channel bridge on the other end.
//

@testable import RayonModule
import XCTest

final class VNCSocketPairTransportTests: XCTestCase {
    private var peer: Int32 = -1
    private var transport: VNCSocketPairTransport!

    override func setUp() {
        var fds: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        transport = VNCSocketPairTransport(fd: fds[0])
        peer = fds[1]
    }

    override func tearDown() {
        transport = nil
        if peer >= 0 { close(peer) }
    }

    private func readPeer(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let n = bytes.withUnsafeMutableBytes { read(peer, $0.baseAddress! + received, count - received) }
            guard n > 0 else { break }
            received += n
        }
        return Array(bytes.prefix(received))
    }

    func testSendsInOrderWithoutStalling() {
        let start = Date()
        for index in 0 ..< 200 {
            transport.send(Data([UInt8(index & 0xFF), 0xAA]))
        }
        let bytes = readPeer(400)
        XCTAssertEqual(bytes.count, 400)
        XCTAssertEqual(stride(from: 0, to: 400, by: 2).map { bytes[$0] }, (0 ..< 200).map { UInt8($0) })
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    /// RFB keeps a read pending for the next server message while input
    /// goes out; a write must not wait for that read to finish.
    func testSendsWhileAReceiveIsPending() async throws {
        let transport = transport!
        let pending = Task { try await transport.receive(maximumLength: 16) }
        try await Task.sleep(for: .milliseconds(100))
        transport.send(Data([1, 2, 3]))
        transport.send(Data([4, 5]))
        transport.send(Data([6]))
        XCTAssertEqual(readPeer(6), [1, 2, 3, 4, 5, 6])
        _ = [UInt8](repeating: 9, count: 1).withUnsafeBytes { write(peer, $0.baseAddress, 1) }
        let received = try await pending.value
        XCTAssertEqual(received, Data([9]))
    }

    func testReceivesWhatArrivesAndThenTheEnd() async throws {
        _ = [UInt8](repeating: 7, count: 10).withUnsafeBytes { write(peer, $0.baseAddress, 10) }
        let data = try await transport.receive(maximumLength: 65536)
        XCTAssertEqual(data, Data(repeating: 7, count: 10))
        close(peer)
        peer = -1
        do {
            _ = try await transport.receive(maximumLength: 65536)
            XCTFail("expected the end of the stream")
        } catch {
            XCTAssertEqual(error as? VNCStreamError, .endOfStream)
        }
    }

    func testCloseWakesAPendingReceive() async {
        let transport = transport!
        let pending = Task { try await transport.receive(maximumLength: 16) }
        try? await Task.sleep(for: .milliseconds(100))
        transport.close()
        let result = await pending.result
        XCTAssertThrowsError(try result.get())
    }
}
