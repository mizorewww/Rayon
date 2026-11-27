//
//  Bench+macOS.swift
//  Rayon
//

#if os(macOS)
    #if DEBUG
        import AppKit
        import MachineStatusView
        import RayonModule
        import RayonTerminal
        import RayonSSH
        import QuartzCore
        import SwiftUI

        extension Notification.Name {
            static let benchFiles = Notification.Name("me.mizorewww.rayon.bench.files")
        }

        /// Filled by an observer on the main run loop.
        @MainActor
        private final class RunLoopLoad {
            var busy = 0.0
            var stretch = 0.0
            var woke = CACurrentMediaTime()
        }

        @MainActor
        enum Bench {
            static func runIfRequested() {
                if ProcessInfo.processInfo.environment["RAYON_PREVIEW_FILES"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Task { await previewFiles() } }
                }
                if ProcessInfo.processInfo.environment["RAYON_BENCH_SETTINGS"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Task { await settings() } }
                }
                if let value = ProcessInfo.processInfo.environment["RAYON_BENCH_HOME"], let count = Int(value) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Task { await home(count) } }
                }
                if ProcessInfo.processInfo.environment["RAYON_BENCH_SEED"] != nil { seed() }
                if let value = ProcessInfo.processInfo.environment["RAYON_BENCH_PAGES"], let count = Int(value) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Task { await pages(count) } }
                }
                guard let value = ProcessInfo.processInfo.environment["RAYON_BENCH_FILES"], let count = Int(value) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Task { await files(count) } }
            }

            static var longest = 0.0

            static func settle(_ action: () -> Void) async -> Double {
                let load = RunLoopLoad()
                let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
                let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, CFIndex.max) { _, activity in
                    MainActor.assumeIsolated {
                        let now = CACurrentMediaTime()
                        if activity == .afterWaiting { load.woke = now } else { load.busy += now - load.woke; load.stretch = max(load.stretch, now - load.woke); load.woke = now }
                    }
                }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                action()
                try? await Task.sleep(nanoseconds: 400_000_000)
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
                longest = load.stretch * 1000
                return load.busy * 1000
            }

            static func report(_ name: String, _ samples: [Double]) {
                let sorted = samples.sorted()
                let median = sorted[sorted.count / 2]
                NSLog("BENCH %@ median %.2f ms  max %.2f ms  n=%d", name, median, sorted.last ?? 0, samples.count)
            }

            static func emptyFilesPage() async -> FileTransferContext {
                let machine = RDMachine(remoteAddress: "203.0.113.10", remotePort: "22", name: "web-01")
                let context = FileTransferContext(machine: machine)
                FileTransferManager.shared.transfers.append(context)
                AppRouter.shared.route = .transfer(context.id)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                while context.processConnection { try? await Task.sleep(nanoseconds: 200_000_000) }
                try? await Task.sleep(nanoseconds: 500_000_000)
                context.connected = true
                context.isProgressRunning = false
                try? await Task.sleep(nanoseconds: 500_000_000)
                return context
            }

            static func previewFiles() async {
                let context = await emptyFilesPage()
                context.currentDir = "/var/log"
                let base = URL(fileURLWithPath: "/var/log")
                let names = ["nginx", "journal", "apt", "private", "auth.log", "syslog", "kern.log", "dpkg.log", "boot.log",
                             "a-very-long-file-name-that-does-not-fit-in-the-name-column-of-the-table-and-is-truncated-in-the-middle-2026-10-11.log.gz",
                             "fail2ban.log", "alternatives.log", "cloud-init.log", "wtmp", "btmp", "lastlog", "ufw.log", "mail.log"]
                context.currentFileList = names.enumerated().map { index, name in
                    let file = SFTPEntry(
                        name: name,
                        size: Int64(index * index * 4321 + 17),
                        permissions: index < 4 ? 0o040755 : 0o100644,
                        modificationDate: Date(timeIntervalSince1970: TimeInterval(1_780_000_000 + index * 86400 * 3)),
                        ownerUID: index < 4 ? 0 : 1000
                    )
                    return FileTransferContext.RemoteFile(base: base, name: name, fstat: file)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                NotificationCenter.default.post(name: .benchFiles, object: nil, userInfo: ["select": 6])
            }

            static func files(_ count: Int) async {
                let context = await emptyFilesPage()
                let base = URL(fileURLWithPath: "/var/log")
                var generator = SystemRandomNumberGenerator()
                let list = (0 ..< count).map { _ in
                    let name = "file-\(Int.random(in: 0 ..< 10_000_000, using: &generator)).log"
                    return FileTransferContext.RemoteFile(base: base, name: name, fstat: SFTPEntry(name: name, size: nil, permissions: nil, modificationDate: nil))
                }
                report("show \(count)", [await settle { context.currentFileList = list }])
                NSLog("BENCH done")
            }

            static func settings() async {
                let router = AppRouter.shared
                router.settingsSelection = "general"
                report("open settings", [await settle { router.route = .settings }])
                NSLog("BENCH done")
            }

            /// Fills an empty store with a large library: 200 servers in 10
            /// folders (one in five with a VNC desktop), 50 identities, 100
            /// snippets in 8 groups and 30 forwards. Addresses are TEST-NET-3.
            static func seed() {
                let store = RayonStore.shared
                guard store.machines.count < 200 else { return }
                let folders = (1 ... 10).map { store.folder(named: "Folder \($0)") ?? store.createFolder(named: "Folder \($0)") }
                let identities = (1 ..< 50).map { index in
                    RDIdentity(username: "user\(index)", publicKey: "ssh-ed25519 AAAA\(index)", comment: index.isMultiple(of: 3) ? "deploy key \(index)" : "", group: "Team \(index % 5)")
                }
                identities.forEach { store.save($0) }
                for index in 0 ..< 200 {
                    var machine = RDMachine(
                        remoteAddress: "203.0.113.\(index % 250 + 1)",
                        remotePort: index.isMultiple(of: 7) ? "2222" : "22",
                        name: "server-\(String(format: "%03d", index))",
                        folderId: index.isMultiple(of: 11) ? nil : folders[index % folders.count].id,
                        lastConnection: Date(timeIntervalSinceNow: -Double(index) * 3600),
                        comment: index.isMultiple(of: 4) ? "rack \(index / 10)" : "",
                        associatedIdentity: index.isMultiple(of: 3) ? nil : identities[index % identities.count].id
                    )
                    if index.isMultiple(of: 5) {
                        machine.remoteDesktopProtocol = .vnc
                        machine.vncPort = "5900"
                    }
                    store.save(machine)
                }
                for index in 0 ..< 100 {
                    store.save(RDSnippet(name: "snippet \(index)", group: "Group \(index % 8)", code: "uptime\ndf -h /\nfree -m # \(index)", comment: index.isMultiple(of: 2) ? "health check" : "", symbol: "terminal"))
                }
                for index in 0 ..< 30 {
                    store.save(RDPortForward(bindPort: 10000 + index, targetHost: "127.0.0.1", targetPort: 5432, usingMachine: store.machines[index].id))
                }
                NSLog("BENCH seeded %d servers, %d identities, %d snippets, %d forwards", store.machines.count, store.identities.count, store.snippets.count, store.portForwards.count)
            }

            /// Switches through every sidebar page, and the Terminal, Files and
            /// Monitor session pages, `count` times; each sample is the main
            /// thread's busy time from the click until the page settles. Then,
            /// on each page, the cost of one change to one server in the store.
            static func pages(_ count: Int) async {
                let router = AppRouter.shared
                let store = RayonStore.shared
                guard let target = store.machines.first?.id else { return }
                if let command = SSHCommandReader(command: "ssh demo@127.0.0.1 -p 1") { router.openTerminal(command: command) }
                guard let terminal = TerminalManager.shared.sessionContexts.last else { return }
                let files = FileTransferContext(machine: RDMachine(remoteAddress: "127.0.0.1", remotePort: "1", name: "bench-files"))
                FileTransferManager.shared.transfers.append(files)
                router.openMonitor(machine: target)
                guard let monitor = MonitorCenter.shared.session(for: target) else { return }
                // RAYON_BENCH_ONLY=servers,monitor cycles just those pages, for a profile of one.
                let only = ProcessInfo.processInfo.environment["RAYON_BENCH_ONLY"]?.split(separator: ",").map(String.init)
                let routes: [(String, Route)] = [
                    ("home", .home), ("dashboard", .dashboard), ("servers", .servers), ("identities", .identities),
                    ("snippets", .snippets), ("forwards", .portForward), ("desktops", .desktops), ("settings", .settings),
                    ("terminal", .terminal(terminal.id)), ("files", .transfer(files.id)), ("monitor", .monitor(monitor.id)),
                ].filter { only?.contains($0.0) ?? true }
                router.route = .home
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                var busy: [String: [Double]] = [:]
                var stretches: [String: [Double]] = [:]
                for _ in 0 ..< count {
                    for (name, route) in routes {
                        busy[name, default: []].append(await settle { router.route = route })
                        stretches[name, default: []].append(longest)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                for (name, _) in routes {
                    report("page \(name) busy", busy[name] ?? [])
                    report("page \(name) longest", stretches[name] ?? [])
                }
                for (name, route) in routes {
                    router.route = route
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    var samples: [Double] = []
                    for _ in 0 ..< max(3, count / 2) {
                        samples.append(await settle { store.updateMachine(target) { $0.lastBanner = UUID().uuidString } })
                    }
                    report("change on \(name)", samples)
                }
                NSLog("BENCH done")
            }

            /// Enters Home from Servers `count` times; the main thread's busy
            /// time and its longest stretch are what a stutter on entry costs.
            static func home(_ count: Int) async {
                let router = AppRouter.shared
                var busy: [Double] = []
                var stretches: [Double] = []
                for _ in 0 ..< count {
                    router.route = .servers
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    busy.append(await settle { router.route = .home })
                    stretches.append(longest)
                }
                report("enter home busy", busy)
                report("enter home longest", stretches)
                NSLog("BENCH done")
            }
        }
    #endif

#endif
