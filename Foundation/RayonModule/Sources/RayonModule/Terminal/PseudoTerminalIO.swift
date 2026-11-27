//
//  PseudoTerminalIO.swift
//  RayonModule
//
//  Reads and writes the controlling side of a pseudo-terminal on dispatch
//  sources, without ever blocking: input the terminal cannot take yet (a
//  paste larger than its buffer, a program that is not reading) waits here
//  and goes out as the terminal drains.
//

#if os(macOS)
    import Darwin
    import Dispatch
    import Foundation
    import os

    final class PseudoTerminalIO: Sendable {
        private let descriptor: Int32
        private let queue = DispatchQueue(label: "me.mizorewww.rayon.pty", qos: .userInteractive)
        private let reader: DispatchSourceRead
        private let writer: DispatchSourceWrite
        private let state = OSAllocatedUnfairLock(initialState: State())

        private struct State {
            /// Input not written yet.
            var pending = Data()
            /// Whether the writer is resumed, waiting for room in the terminal.
            var waitingForRoom = false
            var closed = false
        }

        /// Takes over `descriptor`, a non-blocking terminal, and closes it
        /// in `close()`. `output` is called with what the program writes,
        /// on a queue of this terminal's; `ended` once, when the program's
        /// side has closed.
        init(descriptor: Int32, output: @escaping @Sendable (Data) -> Void, ended: @escaping @Sendable () -> Void) {
            self.descriptor = descriptor
            reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            writer = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
            // The number is closed only once neither source can use it any
            // more: it may be handed to another file the moment it closes.
            let sources = DispatchGroup()
            for source in [reader, writer] as [DispatchSourceProtocol] {
                sources.enter()
                source.setCancelHandler { sources.leave() }
            }
            sources.notify(queue: queue) { Darwin.close(descriptor) }

            reader.setEventHandler { [reader] in
                var buffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    let count = Darwin.read(descriptor, &buffer, buffer.count)
                    if count > 0 {
                        output(Data(buffer[0 ..< count]))
                    } else if count < 0, errno == EAGAIN || errno == EINTR {
                        return
                    } else {
                        reader.cancel()
                        ended()
                        return
                    }
                }
            }
            writer.setEventHandler { [weak self] in self?.flush() }
            reader.resume()
        }

        /// Writes `data` after everything sent before it, returning at once.
        func send(_ data: Data) {
            queue.async { [self] in
                state.withLock { $0.pending.append(data) }
                flush()
            }
        }

        /// Drops what is still unsent and stops reading and writing.
        func close() {
            queue.async { [self] in
                let resumeWriter = state.withLock { state in
                    state.closed = true
                    state.pending = Data()
                    return !state.waitingForRoom
                }
                // A suspended source never finishes cancelling.
                if resumeWriter { writer.resume() }
                writer.cancel()
                reader.cancel()
            }
        }

        /// Writes until the terminal is full, then waits for room.
        private func flush() {
            state.withLock { state in
                guard !state.closed else { return }
                while !state.pending.isEmpty {
                    let (written, error) = state.pending.withUnsafeBytes { bytes in
                        (Darwin.write(descriptor, bytes.baseAddress, bytes.count), errno)
                    }
                    if written > 0 {
                        state.pending.removeFirst(written)
                    } else if written < 0, error == EINTR {
                        continue
                    } else if written < 0, error == EAGAIN {
                        break
                    } else {
                        // The program's side is gone; nothing will read it.
                        state.pending = Data()
                    }
                }
                if state.pending.isEmpty, state.waitingForRoom {
                    writer.suspend()
                    state.waitingForRoom = false
                } else if !state.pending.isEmpty, !state.waitingForRoom {
                    writer.resume()
                    state.waitingForRoom = true
                }
            }
        }
    }
#endif
