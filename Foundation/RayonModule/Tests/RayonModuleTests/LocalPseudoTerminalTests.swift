//
//  LocalPseudoTerminalTests.swift
//  RayonModuleTests
//

#if os(macOS)
    import Darwin
    @testable import RayonModule
    import XCTest

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

        func testMissingExecutableThrows() {
            XCTAssertThrowsError(try LocalPseudoTerminal.spawn(
                executable: "/nonexistent/shell", arguments: ["shell"], environment: [:],
                directory: "/", columns: 80, rows: 24
            ))
        }
    }
#endif
