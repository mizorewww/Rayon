//
//  LocalPseudoTerminal.swift
//  RayonModule
//
//  Starts a process on a new pseudo-terminal: `openpty` here, the process
//  through `rayon_pty_spawn`, which makes the terminal its controlling one
//  (see rayon_pty.c for why that takes fork rather than posix_spawn).
//

#if os(macOS)
    import Darwin
    import RayonPTY

    struct LocalPseudoTerminal {
        let pid: pid_t
        /// The terminal's controlling side, non-blocking, owned by the caller.
        let master: Int32

        struct SpawnError: Error, CustomStringConvertible {
            let call: String
            let code: Int32
            var description: String { "\(call): \(String(cString: strerror(code)))" }
        }

        /// The child leads a new session that the terminal belongs to, so
        /// Ctrl-C and job control work as under `forkpty`.
        /// `arguments` is the full argv, `arguments[0]` included.
        static func spawn(
            executable: String,
            arguments: [String],
            environment: [String: String],
            directory: String,
            columns: Int,
            rows: Int
        ) throws -> LocalPseudoTerminal {
            var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
            var master: Int32 = -1
            var slave: Int32 = -1
            var name = [CChar](repeating: 0, count: 128)
            guard openpty(&master, &slave, &name, nil, &size) == 0 else {
                throw SpawnError(call: "openpty", code: errno)
            }
            // The child opens the terminal by `name`. The parent's slave stays
            // open until then: the last close of a slave resets its size.
            defer { Darwin.close(slave) }

            let argv = arguments.map { strdup($0) } + [nil]
            let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }

            let pid = rayon_pty_spawn(executable, argv, envp, name, directory)
            guard pid > 0 else {
                let code = errno
                Darwin.close(master)
                throw SpawnError(call: "spawn", code: code)
            }
            let fileFlags = fcntl(master, F_GETFL, 0)
            if fileFlags >= 0 { _ = fcntl(master, F_SETFL, fileFlags | O_NONBLOCK) }
            return LocalPseudoTerminal(pid: pid, master: master)
        }
    }
#endif
