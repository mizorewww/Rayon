//
//  TerminalContext+Local.swift
//  RayonModule
//
//  Runs a local login shell (`$SHELL -l`, else `/bin/zsh -l`) on a
//  pseudo-terminal started by `LocalPseudoTerminal`, on macOS.
//

#if os(macOS)
    import Darwin
    import Foundation

    extension TerminalContext {
        func runLocalTerminal() {
            let initial = terminalSize

            let pw = getpwuid(getuid())
            let pwShell = pw?.pointee.pw_shell.flatMap { String(cString: $0) }
            let pwDir = pw?.pointee.pw_dir.flatMap { String(cString: $0) }
            let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? pwShell ?? "/bin/zsh"
            let homeDir = pwDir ?? NSHomeDirectory()
            let user = NSUserName()

            var environment = ProcessInfo.processInfo.environment
            environment["TERM"] = "xterm-256color"
            environment["COLORTERM"] = "truecolor"
            environment["TERM_PROGRAM"] = "Rayon"
            environment["HOME"] = homeDir
            environment["SHELL"] = shellPath
            environment["USER"] = user
            environment["LOGNAME"] = user
            if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }

            let terminal: LocalPseudoTerminal
            do {
                terminal = try LocalPseudoTerminal.spawn(
                    executable: shellPath,
                    arguments: [(shellPath as NSString).lastPathComponent, "-l"],
                    environment: environment,
                    directory: homeDir,
                    columns: max(8, Int(initial.width)),
                    rows: max(8, Int(initial.height))
                )
            } catch {
                putInformation("[!] Failed to start the local shell (\(error)).")
                return
            }
            let pid = terminal.pid
            let masterFD = terminal.master

            let finished = DispatchSemaphore(value: 0)
            let decoder = UTF8StreamDecoder()
            let io = PseudoTerminalIO(descriptor: masterFD) { [weak self] data in
                let text = decoder.decode(data)
                if !text.isEmpty { self?.surface.write(text) }
            } ended: { [weak self] in
                finished.signal()
                self?.uuWakeSemaphore.signal()
            }

            // The shell's exit ends the tab even while a process it left
            // behind keeps the pseudo-terminal open.
            let exit = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global(qos: .utility))
            exit.setEventHandler { [weak self] in
                finished.signal()
                self?.uuWakeSemaphore.signal()
            }
            exit.resume()

            // Typing, a resize, closing the tab and the shell ending each
            // signal the semaphore; nothing else needs a look.
            var lastSize = initial
            while !closed {
                if finished.wait(timeout: .now()) == .success { break }
                uuWakeSemaphore.wait()
                if finished.wait(timeout: .now()) == .success || closed { break }

                let currentSize = terminalSize
                if currentSize != lastSize, currentSize.width >= 8, currentSize.height >= 8 {
                    lastSize = currentSize
                    var ws = winsize()
                    ws.ws_col = UInt16(Int(currentSize.width))
                    ws.ws_row = UInt16(Int(currentSize.height))
                    _ = ioctl(masterFD, TIOCSWINSZ, &ws)
                }

                let typed = getBuffer()
                if !typed.isEmpty { io.send(Data(typed.utf8)) }
            }

            exit.cancel()
            io.close()
            // Reaps a shell that exited; one still running is hung up. Only
            // an unreaped pid is signalled: a reaped one may belong to
            // another process already.
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == 0 { LocalPseudoTerminal.hangUp(pid) }
        }
    }
#endif
