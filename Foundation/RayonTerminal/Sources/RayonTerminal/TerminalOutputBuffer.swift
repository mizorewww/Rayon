import Foundation

/// Ghostty caps output received before attachment at 1 MiB. Keep startup output
/// here until the surface exists, so an early SSH banner/batch result is not lost.
final class TerminalOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Data] = []
    private var attached = false
    private let receive: @Sendable (Data) -> Void

    init(receive: @escaping @Sendable (Data) -> Void) { self.receive = receive }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            if attached { receive(data) } else { pending.append(data) }
        }
    }

    func setAttached(_ value: Bool) {
        lock.withLock {
            attached = value
            if value {
                for data in pending { receive(data) }
                pending.removeAll(keepingCapacity: false)
            }
        }
    }
}
