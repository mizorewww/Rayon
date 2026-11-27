//
//  PseudoTerminalIOTests.swift
//  RayonModuleTests
//
//  The local terminal's input and output: a paste larger than the
//  terminal takes goes out as it drains, closing never waits for a
//  program that does not read, and the descriptor outlives its readers.
//

#if os(macOS)
    import Darwin
    import os
    @testable import RayonModule
    import XCTest

    final class PseudoTerminalIOTests: XCTestCase {
        private func spawn(_ script: String) throws -> LocalPseudoTerminal {
            try LocalPseudoTerminal.spawn(
                executable: "/bin/sh", arguments: ["sh", "-c", script],
                environment: ["PATH": "/usr/bin:/bin"], directory: "/", columns: 80, rows: 24
            )
        }

        private func reap(_ terminal: LocalPseudoTerminal) {
            kill(terminal.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(terminal.pid, &status, 0)
        }

        private func isOpen(_ descriptor: Int32) -> Bool {
            fcntl(descriptor, F_GETFD) != -1
        }

        private func waitUntil(_ condition: () -> Bool, seconds: TimeInterval = 5) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if condition() { return true }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return condition()
        }

        func testAPasteLargerThanTheTerminalArrivesWhole() throws {
            let terminal = try spawn("stty raw -echo; echo ready; head -c 300000 | wc -c")
            defer { reap(terminal) }
            let output = OSAllocatedUnfairLock(initialState: "")
            let io = PseudoTerminalIO(descriptor: terminal.master) { data in
                output.withLock { $0 += String(decoding: data, as: UTF8.self) }
            } ended: {}
            defer { io.close() }
            XCTAssertTrue(waitUntil { output.withLock { $0.contains("ready") } })
            io.send(Data(repeating: UInt8(ascii: "x"), count: 300_000))
            XCTAssertTrue(waitUntil({ output.withLock { $0.contains("300000") } }, seconds: 10), output.withLock { $0 })
        }

        /// Writing used to retry until the terminal took everything, so a
        /// paste into a program that does not read hung the tab for good,
        /// closing it included.
        func testClosingDropsWhatAProgramDoesNotRead() throws {
            let terminal = try spawn("exec sleep 30")
            defer { reap(terminal) }
            let io = PseudoTerminalIO(descriptor: terminal.master) { _ in } ended: {}
            // Lines: the terminal drops a line longer than it holds, but
            // stops taking whole lines once its input queue is full.
            io.send(Data(String(repeating: "echo pasted-line\n", count: 50000).utf8))
            Thread.sleep(forTimeInterval: 0.2)
            io.close()
            XCTAssertTrue(waitUntil({ !isOpen(terminal.master) }, seconds: 2), "closing waited for the paste")
        }

        /// The descriptor was closed right after cancelling the reader,
        /// which may still have been reading it, and its number may by
        /// then belong to another file.
        func testTheDescriptorOutlivesAReaderStillAtWork() throws {
            let terminal = try spawn("echo hello; exec sleep 30")
            defer { reap(terminal) }
            let reading = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let once = OSAllocatedUnfairLock(initialState: false)
            let io = PseudoTerminalIO(descriptor: terminal.master) { _ in
                guard once.withLock({ first in defer { first = true }; return !first }) else { return }
                reading.signal()
                release.wait()
            } ended: {}
            XCTAssertEqual(reading.wait(timeout: .now() + 5), .success)
            io.close()
            Thread.sleep(forTimeInterval: 0.2)
            XCTAssertTrue(isOpen(terminal.master), "closed under a reader")
            release.signal()
            XCTAssertTrue(waitUntil({ !isOpen(terminal.master) }, seconds: 2))
        }
    }
#endif
