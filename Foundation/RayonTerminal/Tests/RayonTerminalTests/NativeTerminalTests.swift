import AppKit
import GhosttyTerminal
import XCTest
@testable import RayonTerminal

final class NativeTerminalTests: XCTestCase {
    @MainActor
    func testRealSurfaceInputOutputResizeFontAndWindowTransfer() async throws {
        _ = NSApplication.shared
        let terminal = RayonTerminalView()
        let title = expectation(description: "OSC title")
        let bell = expectation(description: "bell")
        let input = expectation(description: "keyboard Enter")
        terminal.setupTitleChain { value in
            if value == "Rayon Ghostty Test" { title.fulfill() }
        }
        terminal.setupBellChain { bell.fulfill() }
        terminal.setupBufferChain { value in
            if value.contains("\r") { input.fulfill() }
        }
        // Output arriving before SwiftUI/AppKit presentation must survive.
        terminal.write("before attach\r\n")
        terminal.setTerminalFontSize(with: 16)
        let native = terminal.session.platformView()
        XCTAssertTrue(native === terminal.session.platformView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = native
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        terminal.write("\u{1B}[31m中文 👻\u{1B}[0m\r\n\u{1B}]2;Rayon Ghostty Test\u{07}\u{07}")
        XCTAssertTrue(terminal.session.backend.waitForPendingOutput())
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("before attach") == true)
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("中文 👻") == true)
        XCTAssertTrue(native.sendKey(.enter))
        await fulfillment(of: [title, bell, input], timeout: 5)
        XCTAssertEqual(native.fontSize, 16)

        let originalSize = terminal.requestTerminalSize()
        window.setContentSize(NSSize(width: 900, height: 600))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(terminal.requestTerminalSize().width, originalSize.width)
        terminal.setTerminalFontSize(with: 20)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(native.fontSize, 20)
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("before attach") == true)

        // Push the original banner into scrollback before transferring the view.
        terminal.write((0..<100).map { "history \($0)\r\n" }.joined())
        XCTAssertTrue(terminal.session.backend.waitForPendingOutput())

        let secondWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        secondWindow.isReleasedWhenClosed = false
        native.removeFromSuperview()
        secondWindow.contentView = terminal.session.platformView()
        secondWindow.orderFront(nil)
        defer { secondWindow.close() }
        try await Task.sleep(for: .milliseconds(150))
        terminal.write("after move\r\n")
        XCTAssertTrue(terminal.session.backend.waitForPendingOutput())
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("after move") == true)
        XCTAssertTrue(native.scrollToRow(0))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("before attach") == true)
    }

    @MainActor
    func testLastSessionReferenceMayBeReleasedBySSHWorker() async throws {
        _ = NSApplication.shared
        let owner = SessionOwner()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        weak var native: AppTerminalView?
        autoreleasepool {
            let view = owner.session!.platformView()
            native = view
            window.contentView = view
            window.orderFront(nil)
        }
        try await Task.sleep(for: .milliseconds(100))
        owner.session!.output.write(Data("live teardown surface".utf8))
        XCTAssertTrue(owner.session!.backend.waitForPendingOutput())
        XCTAssertTrue(owner.session!.backend.readViewportText()?.contains("live teardown surface") == true)
        window.contentView = nil
        window.close()
        await Task.detached { owner.releaseSession() }.value
        for _ in 0..<50 where native != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(native, "Detached native surface must be released, without a worker-thread teardown trap")
    }
}

private final class SessionOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var value: RayonTerminalSession? = .init()
    var session: RayonTerminalSession? { lock.withLock { value } }
    func releaseSession() { lock.withLock { value = nil } }
}
