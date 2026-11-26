import Foundation
import XCTest
@testable import RayonTerminal

final class TerminalBridgeTests: XCTestCase {
    func testInputPreservesUnicodeAtEveryByteBoundary() {
        let text = "ls\r\u{1B}[A中文 👻 café\u{03}\u{00}"
        let bytes = Array(text.utf8)
        for split in 0...bytes.count {
            var decoder = TerminalInputDecoder()
            let result = decoder.append(Data(bytes.prefix(split)))
                + decoder.append(Data(bytes.dropFirst(split)))
            XCTAssertEqual(result, text, "split at byte \(split)")
        }
        var decoder = TerminalInputDecoder()
        let result = bytes.map { decoder.append(Data([$0])) }.joined()
        XCTAssertEqual(result, text)
    }

    func testStartupOutputAboveUpstreamLimitIsNotDropped() {
        let received = ReceivedBytes()
        let output = TerminalOutputBuffer { received.append($0) }
        let banner = Data(repeating: 65, count: 2 * 1024 * 1024)
        output.write(banner)
        output.write(Data("end".utf8))
        XCTAssertTrue(received.data.isEmpty)
        output.setAttached(true)
        XCTAssertEqual(received.data, banner + Data("end".utf8))
        output.setAttached(false)
        output.write(Data("next".utf8))
        output.setAttached(true)
        output.write(Data("live".utf8))
        XCTAssertEqual(received.data, banner + Data("endnextlive".utf8))
    }

    @MainActor
    func testInputAndResizeReachClientOnMainThread() async {
        let callbacks = TerminalCallbacks()
        let input = expectation(description: "input")
        let resize = expectation(description: "resize")
        callbacks.setInput { text in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(text, "中文\r")
            input.fulfill()
        }
        callbacks.setResize { size in
            XCTAssertTrue(Thread.isMainThread)
            if size == CGSize(width: 132, height: 43) { resize.fulfill() }
        }
        DispatchQueue.global().async {
            callbacks.receiveInput(Data("中文\r".utf8))
            callbacks.receiveSize(columns: 132, rows: 43)
        }
        await fulfillment(of: [input, resize], timeout: 5)
        XCTAssertEqual(callbacks.terminalSize, CGSize(width: 132, height: 43))
    }
}

private final class ReceivedBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    var data: Data { lock.withLock { bytes } }
    func append(_ value: Data) { lock.withLock { bytes.append(value) } }
}
