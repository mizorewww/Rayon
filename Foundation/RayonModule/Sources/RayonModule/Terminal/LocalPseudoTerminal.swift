//
//  LocalPseudoTerminal.swift
//  RayonModule
//
//  Starts a process on a new pseudo-terminal with `openpty` + `posix_spawn`.
//  `fork()` in a multithreaded GUI process leaves the child with locks other
//  threads held (malloc, the ObjC runtime, `environ`), so the child may only
//  call async-signal-safe functions until it execs. `posix_spawn` keeps all of
//  that in the kernel: argv, envp and the working directory are prepared here,
//  in the parent, and the child runs nothing of ours.
//

#if os(macOS)
    import Darwin

    struct LocalPseudoTerminal {
        let pid: pid_t
        /// The terminal's controlling side, non-blocking, owned by the caller.
        let master: Int32

        struct SpawnError: Error, CustomStringConvertible {
            let call: String
            let code: Int32
            var description: String { "\(call): \(String(cString: strerror(code)))" }
        }

        /// `POSIX_SPAWN_SETSID` makes the child a session leader; the first
        /// terminal it opens as a session leader becomes its controlling
        /// terminal, so job control works as under `forkpty`.
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

            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, name, O_RDWR, 0)
            posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDOUT_FILENO)
            posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDERR_FILENO)
            posix_spawn_file_actions_addchdir_np(&actions, directory)

            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            // CLOEXEC_DEFAULT: no descriptor of the app leaks into the shell.
            let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
            posix_spawnattr_setflags(&attributes, Int16(flags))
            var allSignals = sigset_t()
            sigfillset(&allSignals)
            posix_spawnattr_setsigdefault(&attributes, &allSignals)
            var noSignals = sigset_t()
            sigemptyset(&noSignals)
            posix_spawnattr_setsigmask(&attributes, &noSignals)

            let argv = arguments.map { strdup($0) } + [nil]
            let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }

            var pid: pid_t = 0
            let result = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
            guard result == 0 else {
                Darwin.close(master)
                throw SpawnError(call: "posix_spawn", code: result)
            }
            let fileFlags = fcntl(master, F_GETFL, 0)
            if fileFlags >= 0 { _ = fcntl(master, F_SETFL, fileFlags | O_NONBLOCK) }
            return LocalPseudoTerminal(pid: pid, master: master)
        }
    }
#endif
