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
            let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: DispatchQueue.global(qos: .userInteractive))
            readSource.setEventHandler { [weak self] in
                guard let self else { return }
                var buf = [UInt8](repeating: 0, count: 65536)
                while true {
                    let n = Darwin.read(masterFD, &buf, buf.count)
                    if n > 0 {
                        let text = decoder.decode(Data(buf[0 ..< n]))
                        if !text.isEmpty {
                            self.surface.write(text)
                        }
                    } else if n == 0 {
                        finished.signal()
                        self.uuWakeSemaphore.signal()
                        break
                    } else {
                        if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                            break
                        }
                        finished.signal()
                        self.uuWakeSemaphore.signal()
                        break
                    }
                }
            }
            readSource.resume()

            var lastSize = initial
            while !closed {
                if finished.wait(timeout: .now()) == .success { break }
                _ = uuWakeSemaphore.wait(timeout: .now() + 0.5)
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
                if !typed.isEmpty {
                    let data = Data(typed.utf8)
                    data.withUnsafeBytes { raw in
                        guard let base = raw.baseAddress else { return }
                        var offset = 0
                        while offset < raw.count {
                            let written = Darwin.write(masterFD, base + offset, raw.count - offset)
                            if written > 0 {
                                offset += written
                            } else if written < 0, errno == EINTR {
                                continue
                            } else if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                                usleep(1000)
                                continue
                            } else {
                                break
                            }
                        }
                    }
                }

                var status: Int32 = 0
                let waited = waitpid(pid, &status, WNOHANG)
                if waited == pid {
                    break
                }
            }

            readSource.cancel()
            Darwin.close(masterFD)
            kill(pid, SIGHUP)
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
        }
    }
#endif
