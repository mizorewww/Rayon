//
//  LocalPseudoTerminalTests.swift
//  RayonModuleTests
//

#if os(macOS)
    import Darwin
    import os
    @testable import RayonModule
    import RayonPTY
    import XCTest

    private let testProcess = getpid()
    /// Written to by a signal handler of this process that runs in a
    /// forked child, before the child has reset its handlers.
    private let inChildMarker: (read: Int32, write: Int32) = {
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        _ = fcntl(fds[0], F_SETFL, O_NONBLOCK)
        return (fds[0], fds[1])
    }()

    private func markIfInChild(_: Int32) {
        guard getpid() != testProcess else { return }
        var byte: UInt8 = 1
        _ = write(inChildMarker.write, &byte, 1)
    }

    final class LocalPseudoTerminalTests: XCTestCase {
        /// The spawned shell owns its terminal (job control needs that), runs
        /// in the given directory with the given environment and size, and
        /// inherits none of the parent's descriptors.
        func testSpawnedProcessOwnsItsTerminal() throws {
            let script = """
            echo "dir=$(pwd -P)"; echo "var=$RAYON_TEST"; echo "size=$(stty size)"
            echo ctty > /dev/tty && echo "ctty=ok"
            [ "$(ps -o pgid= -p $$ | tr -d ' ')" = "$(ps -o tpgid= -p $$ | tr -d ' ')" ] && echo "foreground=ok"
            [ -e /dev/fd/3 ] && echo "leak=fd3" || echo "leak=none"
            """
            // Holds fd 3 open in the parent; the child must not inherit it.
            let held = open("/dev/null", O_RDONLY)
            defer { close(held) }
            // zsh, not sh: bash takes a terminal it opens as its own, which
            // hid that posix_spawn never made the terminal the shell's.
            let terminal = try LocalPseudoTerminal.spawn(
                executable: "/bin/zsh",
                arguments: ["zsh", "-f", "-c", script],
                environment: ["RAYON_TEST": "spawned", "PATH": "/usr/bin:/bin"],
                directory: "/private/tmp",
                columns: 91,
                rows: 27
            )
            defer { close(terminal.master) }

            var output = ""
            var buffer = [UInt8](repeating: 0, count: 4096)
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                let count = read(terminal.master, &buffer, buffer.count)
                if count > 0 {
                    output += String(decoding: buffer[0 ..< count], as: UTF8.self)
                } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                    break
                } else {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            var status: Int32 = 0
            waitpid(terminal.pid, &status, 0)

            XCTAssertTrue(output.contains("dir=/private/tmp"), output.debugDescription)
            XCTAssertTrue(output.contains("var=spawned"), output.debugDescription)
            XCTAssertTrue(output.contains("size=27 91"), output.debugDescription)
            XCTAssertTrue(output.contains("ctty=ok"), output.debugDescription)
            XCTAssertTrue(output.contains("foreground=ok"), output.debugDescription)
            XCTAssertTrue(output.contains("leak=none"), output.debugDescription)
        }

        /// Signals are blocked only while the child is forked: the caller's
        /// mask is as it was, and the child starts with nothing blocked.
        func testTheCallersSignalMaskIsKept() throws {
            var blocked = sigset_t()
            sigemptyset(&blocked)
            sigaddset(&blocked, SIGUSR2)
            var previous = sigset_t()
            pthread_sigmask(SIG_BLOCK, &blocked, &previous)
            defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
            let terminal = try LocalPseudoTerminal.spawn(
                executable: "/bin/zsh", arguments: ["zsh", "-f", "-c", "ps -o sigmask= -p $$"],
                environment: ["PATH": "/usr/bin:/bin"], directory: "/", columns: 80, rows: 24
            )
            defer { close(terminal.master) }
            var after = sigset_t()
            pthread_sigmask(SIG_SETMASK, nil, &after)
            XCTAssertEqual(sigismember(&after, SIGUSR2), 1)
            XCTAssertEqual(sigismember(&after, SIGUSR1), sigismember(&previous, SIGUSR1))

            var output = ""
            var buffer = [UInt8](repeating: 0, count: 256)
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                let count = read(terminal.master, &buffer, buffer.count)
                if count > 0 {
                    output += String(decoding: buffer[0 ..< count], as: UTF8.self)
                } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                    break
                } else {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            var status: Int32 = 0
            waitpid(terminal.pid, &status, 0)
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "0", "the child starts with signals blocked")
        }

        /// A signal arriving between fork and the child resetting its
        /// handlers ran this process's handler in the child, on memory
        /// another thread may have held when it forked. Resizing the
        /// terminal sends SIGWINCH to the child that just made it its own:
        /// while children spawn on it, none may run the handler.
        func testNoHandlerOfThisProcessRunsInTheChild() throws {
            _ = (testProcess, inChildMarker)
            var master: Int32 = -1
            var slave: Int32 = -1
            var name = [CChar](repeating: 0, count: 128)
            XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
            close(slave)
            defer { close(master) }
            let previous = signal(SIGWINCH, markIfInChild)
            defer { signal(SIGWINCH, previous) }

            let resizing = OSAllocatedUnfairLock(initialState: true)
            let resized = DispatchSemaphore(value: 0)
            Thread.detachNewThread { [master] in
                var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
                while resizing.withLock({ $0 }) {
                    size.ws_col = size.ws_col == 80 ? 81 : 80
                    _ = ioctl(master, TIOCSWINSZ, &size)
                }
                resized.signal()
            }
            let argv: [UnsafeMutablePointer<CChar>?] = [strdup("true"), nil]
            let envp: [UnsafeMutablePointer<CChar>?] = [nil]
            defer { argv.forEach { free($0) } }
            for _ in 0 ..< 100 {
                let pid = rayon_pty_spawn("/usr/bin/true", argv, envp, name, "/")
                XCTAssertGreaterThan(pid, 0)
                var status: Int32 = 0
                if pid > 0 { waitpid(pid, &status, 0) }
            }
            resizing.withLock { $0 = false }
            resized.wait()

            var marks = [UInt8](repeating: 0, count: 4096)
            let ran = read(inChildMarker.read, &marks, marks.count)
            XCTAssertLessThanOrEqual(ran, 0, "a handler of this process ran in \(ran) children")
        }

        /// A shell that outlives the hangup (here it ignores it) is reaped
        /// when it exits, not left a zombie.
        func testAHungUpShellIsReapedWhenItExits() throws {
            let terminal = try LocalPseudoTerminal.spawn(
                executable: "/bin/zsh", arguments: ["zsh", "-f", "-c", "trap '' HUP; sleep 0.5"],
                environment: ["PATH": "/usr/bin:/bin"], directory: "/", columns: 80, rows: 24
            )
            defer { close(terminal.master) }
            Thread.sleep(forTimeInterval: 0.2)
            LocalPseudoTerminal.hangUp(terminal.pid)
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline, kill(terminal.pid, 0) == 0 {
                Thread.sleep(forTimeInterval: 0.05)
            }
            XCTAssertNotEqual(kill(terminal.pid, 0), 0, "the shell is still a process, or a zombie")
        }

        func testMissingExecutableThrows() {
            XCTAssertThrowsError(try LocalPseudoTerminal.spawn(
                executable: "/nonexistent/shell", arguments: ["shell"], environment: [:],
                directory: "/", columns: 80, rows: 24
            ))
        }
    }
#endif
