//
//  ServerInfo.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/12.
//

import Foundation
import NSRemoteShell

/// One round of a server's readings. A value, so a monitor publishes a
/// whole round at once and views redraw once per round.
public struct ServerStatus: Equatable, Sendable {
    public var processor: ProcessorInfo = .init()
    public var fileSystem: FileSystemInfo = .init()
    public var memory: MemoryInfo = .init()
    public var system: SystemInfo = .init()
    public var network: NetworkInfo = .init()
    public var processes: TopProcessesInfo = .init()
    /// Most servers have no GPU.
    public var graphics: GraphicsInfo?

    public init() {}
}

extension ServerStatus {
    /// The merged monitor script echoes this marker on its own line ahead
    /// of each section; `ProcParsers.splitMonitorSections` only opens a
    /// section on a full-line match, which kernel /proc payloads, df rows
    /// and os-release assignments can never produce. That is what the old
    /// "[*******]" token could not promise inside two samples of one file.
    static let sectionMarkerPrefix = "<<<RAYON-SECTION:"
    static let sectionMarkerSuffix = ">>>"

    /// The parsers read decimal points and English labels; a server whose
    /// login sets a German or French locale would print decimal commas
    /// and translated headers. Every script runs in the C locale.
    static let localeExport = "LC_ALL=C; export LC_ALL"

    /// `nvidia-smi` stays a command of its own: it is slow and missing on
    /// most machines, and its failure must not cost the other sections.
    static let graphicsScript = localeExport + "; nvidia-smi --query-gpu=driver_version,uuid,name,memory.total,memory.used,memory.free,vbios_version,fan.speed,utilization.gpu,utilization.memory --format=csv,noheader,nounits 2>/dev/null || echo \"no nvidia gpu available\""

    /// Hands `script` to `/bin/sh` whatever the login shell is. An exec
    /// channel runs its command through the user's login shell, so POSIX
    /// syntax sent bare fails under fish or csh; wrapped like this every
    /// shell only sees a command name and one single-quoted word. Single
    /// quotes inside the script are closed, escaped and reopened. csh
    /// rejects a newline inside quotes, so the script must be one line.
    /// RayonModule keeps its own copy (`RemoteShellCommand.posix`): it does
    /// not depend on MachineStatus, and the two only share NSRemoteShell,
    /// which is Objective-C.
    static func posixShellCommand(_ script: String) -> String {
        assert(!script.contains("\n"), "csh cannot take a newline inside quotes")
        return "/bin/sh -c '" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The monitor script, ready for any login shell.
    static func monitorCommand(includeStatic: Bool) -> String {
        posixShellCommand(monitorScript(includeStatic: includeStatic))
    }

    /// The GPU probe, ready for any login shell.
    static let graphicsCommand = posixShellCommand(graphicsScript)

    /// One remote run that reads every payload behind markers, so a
    /// refresh costs one exec channel and no remote waiting: CPU and
    /// network rates come from the difference to the previous round's
    /// counters, kept by `ServerStatusSampler`. Linux reads /proc; Darwin
    /// uses its native tools. Static payloads join only while
    /// `includeStatic` — they cannot change while a connection stays up.
    /// The script is POSIX sh on one line; servers get it through
    /// `monitorCommand`.
    static func monitorScript(includeStatic: Bool) -> String {
        var sections = [
            ("platform", "echo \"$RAYON_KERNEL\""),
            // Linux: seconds since boot, also the clock rates are taken over.
            ("uptime", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /bin/date +%s; /usr/sbin/sysctl -n kern.boottime; else /bin/cat /proc/uptime; fi"),
            // Darwin has no jiffies file; each process's accumulated user and
            // total CPU time, differenced per pid, gives the same reading.
            ("cpu", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /bin/ps -A -o pid=,state=,utime=,time=; else /bin/cat /proc/stat; fi"),
            ("ncpu", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /usr/sbin/sysctl -n hw.logicalcpu; fi"),
            ("net", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /usr/sbin/netstat -ibn; else /bin/cat /proc/net/dev; fi"),
            ("mem", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /usr/sbin/sysctl hw.memsize hw.pagesize vm.swapusage; /usr/bin/vm_stat; else /bin/cat /proc/meminfo; fi"),
            ("df", "/bin/df -Pk"),
            ("loadavg", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /usr/sbin/sysctl -n vm.loadavg; else /bin/cat /proc/loadavg; fi"),
            // The busiest processes, the header and a dozen rows each: room
            // for the ps and head of this probe, which the parser drops.
            // busybox's ps cannot pick columns or sort, so it prints its
            // plain listing once and the parser orders it.
            ("procs-cpu", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /bin/ps -Ao pid,user,pcpu,pmem,rss,comm -r | /usr/bin/head -13; elif RAYON_PS=\"$(ps -eo pid,user,pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null)\"; then echo \"$RAYON_PS\" | head -13; else ps 2>/dev/null | head -500; fi"),
            ("procs-mem", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /bin/ps -Ao pid,user,pcpu,pmem,rss,comm -m | /usr/bin/head -13; else ps -eo pid,user,pcpu,pmem,rss,comm --sort=-rss 2>/dev/null | head -13; fi"),
        ]
        if includeStatic {
            sections += [
                ("hostname", "/bin/hostname 2>/dev/null || hostname 2>/dev/null || echo \"localhost\""),
                ("os-release", "if [ \"$RAYON_KERNEL\" = Darwin ]; then /usr/bin/sw_vers; else /bin/cat /etc/os-release; fi"),
            ]
        }
        let commands = sections.map { name, command in
            "echo '\(sectionMarkerPrefix)\(name)\(sectionMarkerSuffix)'; \(command)"
        }
        return ([localeExport, "RAYON_KERNEL=\"$(/usr/bin/uname -s 2>/dev/null || uname -s)\""] + commands)
            .joined(separator: "; ")
    }

    static func downloadResultFrom(shell: NSRemoteShell, command: String, timeout: Double) -> String {
        guard shell.isConnected, shell.isAuthenticated else {
            return ""
        }
        var result = ""
        shell.beginExecute(
            withCommand: command,
            withTimeout: NSNumber(value: timeout),
            withOnCreate: {},
            withOutput: { result.append($0) },
            withContinuationHandler: nil
        )
        return result
    }
}
