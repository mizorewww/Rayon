import Foundation
import Synchronization

/// Registration may happen on an SSH worker. Delivery stays on the main actor,
/// like the old WebKit message handlers. Never invoke a client while holding the lock.
final class TerminalCallbacks: Sendable {
    private struct State {
        var input: (@MainActor (String) -> Void)?
        var title: (@MainActor (String) -> Void)?
        var bell: (@MainActor () -> Void)?
        var resize: (@MainActor (CGSize) -> Void)?
        var size = CGSize(width: 80, height: 40)
        var requestedFontSize = 14
        var decoder = TerminalInputDecoder()
    }

    private let state = Mutex(State())

    func setInput(_ callback: (@MainActor (String) -> Void)?) {
        state.withLock {
            $0.input = callback
            $0.decoder.reset()
        }
    }
    func setTitle(_ callback: (@MainActor (String) -> Void)?) { state.withLock { $0.title = callback } }
    func setBell(_ callback: (@MainActor () -> Void)?) { state.withLock { $0.bell = callback } }
    func setResize(_ callback: (@MainActor (CGSize) -> Void)?) {
        state.withLock { $0.resize = callback }
        DispatchQueue.main.async { [self] in
            let (callback, value) = state.withLock { ($0.resize, $0.size) }
            callback?(value)
        }
    }

    var terminalSize: CGSize { state.withLock { $0.size } }
    var fontSize: Int { state.withLock { $0.requestedFontSize } }
    func setFontSize(_ value: Int) { state.withLock { $0.requestedFontSize = value } }

    func receiveInput(_ data: Data) {
        DispatchQueue.main.async { [self] in
            let (callback, text) = state.withLock { ($0.input, $0.decoder.append(data)) }
            if !text.isEmpty { callback?(text) }
        }
    }

    func receiveSize(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        DispatchQueue.main.async { [self] in
            let value = CGSize(width: columns, height: rows)
            let callback = state.withLock {
                $0.size = value
                return $0.resize
            }
            callback?(value)
        }
    }

    @MainActor func receiveTitle(_ value: String) { state.withLock { $0.title }?(value) }
    @MainActor func receiveBell() { state.withLock { $0.bell }?() }
}

/// The session takes input as String. Hold incomplete UTF-8 suffixes instead of
/// replacing a Chinese character/emoji when Ghostty splits it across callbacks.
struct TerminalInputDecoder: Sendable {
    private var pending = Data()

    mutating func reset() {
        pending.removeAll(keepingCapacity: false)
    }

    mutating func append(_ data: Data) -> String {
        pending.append(data)
        guard !pending.isEmpty else { return "" }
        var end = pending.count
        for back in 1 ... min(3, pending.count) {
            let byte = pending[pending.startIndex + pending.count - back]
            if byte & 0xC0 == 0x80 { continue }
            let count: Int
            switch byte {
            case 0xC2...0xDF: count = 2
            case 0xE0...0xEF: count = 3
            case 0xF0...0xF4: count = 4
            default: count = 1
            }
            if count > back { end = pending.count - back }
            break
        }
        let text = String(decoding: pending.prefix(end), as: UTF8.self)
        if end == pending.count {
            pending.removeAll(keepingCapacity: true)
        } else {
            pending = Data(pending.dropFirst(end))
        }
        return text
    }
}
