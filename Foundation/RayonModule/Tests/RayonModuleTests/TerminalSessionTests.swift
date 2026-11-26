//
//  TerminalSessionTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

@MainActor
final class TerminalShutdownTests: XCTestCase {
    /// A session that ends turns the modes a program may have left on off
    /// before it says so, and keeps nothing typed for the next one.
    func testAnEndingSessionResetsTerminalModes() async throws {
        RayonStore.shared.openInterfaceAutomatically = false
        let surface = RecordingSurface()
        // Nothing listens on port 1: the session ends at once.
        let context = TerminalContext(machine: RDMachine(remoteAddress: "127.0.0.1", remotePort: "1", name: "closed"), surface: surface)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !surface.text.contains("Connection Closed") {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let text = surface.text
        let reset = try XCTUnwrap(text.range(of: TerminalContext.modeReset), text)
        let closed = try XCTUnwrap(text.range(of: "Connection Closed"))
        XCTAssertLessThan(reset.lowerBound, closed.lowerBound)
        context.insertBuffer("stale")
        XCTAssertEqual(context.getBuffer(), "")
    }
}

/// A terminal renderer that keeps what it is sent, and types on request.
final class RecordingSurface: TerminalSessionSurface, @unchecked Sendable {
    private let lock = NSLock()
    private var written = ""
    private var buffer: ((String) -> Void)?
    var text: String { lock.withLock { written } }
    func type(_ string: String) { buffer?(string) }
    func write(_ string: String) { lock.withLock { written += string } }
    func setupBellChain(_: @escaping () -> Void) {}
    func setupBufferChain(_ callback: @escaping (String) -> Void) { buffer = callback }
    func setupTitleChain(_: @escaping (String) -> Void) {}
    func setupSizeChain(_: @escaping (CGSize) -> Void) {}
}
