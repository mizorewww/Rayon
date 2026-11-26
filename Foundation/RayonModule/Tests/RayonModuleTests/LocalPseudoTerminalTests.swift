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
            let terminal = try LocalPseudoTerminal.spawn(
                executable: "/bin/sh",
                arguments: ["sh", "-c", script],
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

        func testMissingExecutableThrows() {
            XCTAssertThrowsError(try LocalPseudoTerminal.spawn(
                executable: "/nonexistent/shell", arguments: ["shell"], environment: [:],
                directory: "/", columns: 80, rows: 24
            ))
        }
    }
#endif
