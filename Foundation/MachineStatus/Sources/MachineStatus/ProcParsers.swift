//
//  ProcParsers.swift
//  MachineStatus
//
//  Pure parsers for Linux /proc and os-release payloads, extracted from
//  the ServerStatus remote initializers so they can be unit tested
//  offline with fixtures.
//

import Foundation

enum ProcParsers {
    /// Splits on runs of whitespace: /proc files and tool outputs pad
    /// columns with variable-width spaces.
    static func splitWhitespaceRuns(_ line: String) -> [Substring] {
        line.split(whereSeparator: \.isWhitespace)
    }

    // MARK: - /proc/meminfo

    /// Parses `/proc/meminfo` content into a keyed dictionary (values in kB).
    static func parseMeminfo(_ raw: String) -> [String: Double] {
        var info = [String: Double]()
        for line in raw.components(separatedBy: "\n") where line.count > 0 {
            let line = line.replacingOccurrences(of: ":", with: "")
            let cut = splitWhitespaceRuns(line)
            guard cut.count == 3, cut[2].uppercased() == "KB" else {
                continue
            }
            info[cut[0].uppercased()] = Double(cut[1])
        }
        return info
    }

    // MARK: - /proc/stat

    /// Parses one `/proc/stat` sample into the aggregate "cpu" row and
    /// per-core rows. Kernels before 2.6.33 print fewer columns; missing
    /// trailing columns read as zero.
    static func parseProcStat(_ raw: String)
        -> (summary: ServerStatus.ProcessInfoElement?, cores: [String: ServerStatus.ProcessInfoElement])
    {
        var result = [String: ServerStatus.ProcessInfoElement]()
        var summary: ServerStatus.ProcessInfoElement?
        for line in raw.components(separatedBy: "\n") {
            let fields = splitWhitespaceRuns(line)
            guard let key = fields.first, key.hasPrefix("cpu"), fields.count >= 5 else {
                continue
            }
            let counters = fields.dropFirst().compactMap { UInt64($0) }
            guard counters.count == fields.count - 1 else { continue }
            func value(_ index: Int) -> UInt64 {
                index < counters.count ? counters[index] : 0
            }
            let element = ServerStatus.ProcessInfoElement(
                user: value(0),
                nice: value(1),
                system: value(2),
                idle: value(3),
                iowait: value(4),
                irq: value(5),
                softIrq: value(6),
                steal: value(7)
            )
            if key == "cpu" {
                summary = element
            } else {
                result[String(key)] = element
            }
        }
        return (summary, result)
    }

    /// Computes usage percentages between two /proc/stat samples.
    /// Returns zeros when counters did not advance (idle machine) or went
    /// back (a counter reset), rather than dividing by zero or wrapping.
    static func calculatePercent(
        priv: ServerStatus.ProcessInfoElement,
        curr: ServerStatus.ProcessInfoElement
    ) -> ServerStatus.ProcessPercentInfo {
        guard curr.total > priv.total else {
            return ServerStatus.ProcessPercentInfo()
        }
        let total = Double(curr.total - priv.total)
        func share(_ counter: KeyPath<ServerStatus.ProcessInfoElement, UInt64>) -> Float {
            let now = curr[keyPath: counter]
            let before = priv[keyPath: counter]
            return now > before ? Float(Double(now - before) / total * 100) : 0
        }
        let system = share(\.system)
        let user = share(\.user)
        let iowait = share(\.iowait)
        let nice = share(\.nice)
        return ServerStatus.ProcessPercentInfo(
            system: system,
            user: user,
            iowait: iowait,
            nice: nice,
            sum: min(100, system + user + iowait + nice)
        )
    }

    // MARK: - merged monitor script

    /// Splits the merged monitor script's output into named sections. The
    /// script echoes a marker line ahead of each command's payload and
    /// only a full-line match opens a section; kernel /proc payloads, df
    /// rows and os-release assignments can never consist of just the
    /// marker, so sections cannot collide with remote content the way a
    /// bare token like "[*******]" could sit inside one payload.
    static func splitMonitorSections(_ raw: String) -> [String: String] {
        var sections = [String: String]()
        var current: String?
        for line in raw.components(separatedBy: "\n") {
            // whitespacesAndNewlines also eats a stray \r: the channel is
            // not a pty so markers end in \n, but a payload that slipped a
            // CR in must not make a marker unrecognizable.
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(ServerStatus.sectionMarkerPrefix),
               trimmed.hasSuffix(ServerStatus.sectionMarkerSuffix)
            {
                let name = String(
                    trimmed
                        .dropFirst(ServerStatus.sectionMarkerPrefix.count)
                        .dropLast(ServerStatus.sectionMarkerSuffix.count)
                )
                current = name
                sections[name] = ""
                continue
            }
            if let current {
                sections[current, default: ""] += line + "\n"
            }
        }
        return sections
    }

    // MARK: - /proc/uptime

    /// Parses the first field of `/proc/uptime` ("773229.50 1531748.20").
    static func parseUptime(_ intake: String) -> Double {
        Double(splitWhitespaceRuns(intake).first ?? "") ?? 0
    }

    // MARK: - /etc/os-release

    static func stripSurroundingQuotes(_ str: String) -> String {
        guard str.count > 2 else { return str }
        let doubleQuoted = str.hasPrefix("\"") && str.hasSuffix("\"")
        let singleQuoted = str.hasPrefix("'") && str.hasSuffix("'")
        guard doubleQuoted || singleQuoted else { return str }
        return String(str.dropFirst().dropLast())
    }

    /// Extracts a display name from /etc/os-release content, preferring
    /// PRETTY_NAME over NAME, unquoting the value.
    static func parseOsReleaseName(_ intake: String) -> String {
        var pretty: String?
        var name: String?
        for item in intake.components(separatedBy: "\n") {
            if item.hasPrefix("PRETTY_NAME=") {
                pretty = String(item.dropFirst("PRETTY_NAME=".count))
                break
            }
            if item.hasPrefix("NAME=") {
                name = String(item.dropFirst("NAME=".count))
            }
        }
        if let pretty {
            return stripSurroundingQuotes(pretty)
        }
        if let name {
            return stripSurroundingQuotes(name)
        }
        return "Generic Linux"
    }

    // MARK: - /proc/loadavg

    /// Parses `/proc/loadavg` ("0.27 0.34 0.39 2/916 23817") into
    /// load averages and process counters.
    static func parseLoadavg(_ intake: String) -> ServerStatus.SystemLoadInternal {
        var ret = ServerStatus.SystemLoadInternal()
        let cut = splitWhitespaceRuns(intake)
        guard cut.count == 5 else { return .init() }
        if let l1 = Float(cut[0]), l1 != .infinity { ret.load1avg = l1 } else { return .init() }
        if let l5 = Float(cut[1]), l5 != .infinity { ret.load5avg = l5 } else { return .init() }
        if let l15 = Float(cut[2]), l15 != .infinity { ret.load15avg = l15 } else { return .init() }
        let process = cut[3].components(separatedBy: "/")
        if process.count == 2,
           let running = Int(process[0]),
           let total = Int(process[1])
        {
            ret.runningProcess = running
            ret.totalProcess = total
        } else {
            return .init()
        }
        return ret
    }

    // MARK: - df -Pk

    /// Formats a 1024-block count the way `df -h` would ("935M", "98G",
    /// "1.8T"), so the model keeps serving display-ready strings.
    static func formatKilobytes(_ kilobytes: Int) -> String {
        let units = ["K", "M", "G", "T", "P"]
        var value = Double(kilobytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 || value >= 10 {
            return "\(Int(value.rounded()))\(units[index])"
        }
        return String(format: "%.1f%@", value, units[index])
    }

    /// Parses `df -Pk` output (POSIX: one line per filesystem, sizes in
    /// 1024-blocks) into display-ready elements. Unlike `df -h`, -P never
    /// wraps a long device name onto its own line, and the mount point is
    /// the trailing columns, so spaces in it survive.
    static func parseDfPk(_ raw: String) -> [ServerStatus.FileSystemInfo.FileSystemInfoElement] {
        var result = [ServerStatus.FileSystemInfo.FileSystemInfoElement]()
        for line in raw.components(separatedBy: "\n").dropFirst() where line.count > 0 {
            let cut = splitWhitespaceRuns(line)
            guard cut.count >= 6,
                  let size = Int(cut[1]),
                  let used = Int(cut[2]),
                  let free = Int(cut[3]),
                  cut[4].hasSuffix("%"),
                  let percent = Float(cut[4].dropLast())
            else {
                continue
            }
            let mount = cut[5...].joined(separator: " ")
            // Skip pseudo and empty filesystems (udev reports 0 available).
            guard mount.hasPrefix("/"), free > 0 else {
                continue
            }
            result.append(.init(
                mountPoint: mount,
                size: formatKilobytes(size),
                used: formatKilobytes(used),
                free: formatKilobytes(free),
                percent: percent
            ))
        }
        return result
    }

    // MARK: - ps

    enum ProcessOrder {
        case cpu
        case memory
    }

    /// Reads a `ps` listing by its header, so procps
    /// (`ps -eo pid,user,pcpu,pmem,rss,comm`), macOS (`ps -Ao …`) and plain
    /// busybox `ps` (`PID USER TIME COMMAND`, or with VSZ and STAT) all
    /// parse. The command is the last column and keeps its spaces. Rows
    /// of the probe itself (`ps`, `head`) are dropped. Ordered by `order`
    /// when the listing has that column, else left as `ps` printed them.
    static func parseProcessList(_ raw: String, order: ProcessOrder, limit: Int = 10) -> [ServerStatus.TopProcess] {
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let headerIndex = lines.firstIndex(where: { splitWhitespaceRuns($0).contains("PID") }) else {
            return []
        }
        let header = splitWhitespaceRuns(lines[headerIndex]).map { $0.uppercased() }
        guard let commandName = header.last,
              ["COMMAND", "COMM", "CMD", "ARGS"].contains(commandName),
              let pidColumn = header.firstIndex(of: "PID")
        else {
            return []
        }
        let userColumn = header.firstIndex { $0 == "USER" || $0 == "UID" }
        let cpuColumn = header.firstIndex { $0 == "%CPU" || $0 == "CPU" }
        let memoryColumn = header.firstIndex(of: "%MEM")
        let residentColumn = header.firstIndex(of: "RSS")

        var processes: [ServerStatus.TopProcess] = []
        for line in lines[(headerIndex + 1)...] {
            let fields = line.split(maxSplits: header.count - 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == header.count, let pid = Int(fields[pidColumn]) else {
                continue
            }
            // The split leaves the padding before the last column on it.
            let rawCommand = fields[header.count - 1].trimmingCharacters(in: .whitespaces)
            let command = processName(rawCommand, isExecutablePath: commandName == "COMM")
            guard !command.isEmpty, !isMonitorProbe(command) else {
                continue
            }
            processes.append(.init(
                pid: pid,
                user: userColumn.map { String(fields[$0]) } ?? "",
                command: command,
                cpuPercent: cpuColumn.flatMap { Double(fields[$0]) },
                memoryPercent: memoryColumn.flatMap { Double(fields[$0]) },
                residentKB: residentColumn.flatMap { parseKilobytes(fields[$0]) }
            ))
        }

        let key: (ServerStatus.TopProcess) -> Double? = switch order {
        case .cpu: { $0.cpuPercent }
        case .memory: { $0.residentKB ?? $0.memoryPercent }
        }
        if processes.contains(where: { key($0) != nil }) {
            // Stable: equal values keep the order ps printed them in.
            processes = processes.enumerated()
                .sorted { lhs, rhs in
                    let left = key(lhs.element) ?? -1
                    let right = key(rhs.element) ?? -1
                    return left != right ? left > right : lhs.offset < rhs.offset
                }
                .map(\.element)
        }
        return Array(processes.prefix(limit))
    }

    /// The monitor's own `ps` and `head`, and on busybox, which prints
    /// command lines, the sh running the monitor script.
    static func isMonitorProbe(_ command: String) -> Bool {
        let program = command.split(separator: " ", maxSplits: 1).first ?? ""
        return program == "ps" || program == "head" || command.contains("RAYON_KERNEL")
    }

    /// macOS `comm` is the executable's whole path, spaces and all; busybox
    /// prints the command line. Both are cut to the program's name, and
    /// busybox keeps its arguments. Linux `comm` and kernel threads
    /// (`[kworker/0:1]`) stay as they are.
    static func processName(_ raw: String, isExecutablePath: Bool) -> String {
        guard raw.hasPrefix("/") else { return raw }
        if isExecutablePath {
            return (raw as NSString).lastPathComponent
        }
        let parts = raw.split(separator: " ", maxSplits: 1)
        let program = (String(parts[0]) as NSString).lastPathComponent
        return parts.count > 1 ? "\(program) \(parts[1])" : program
    }

    /// `ps` prints RSS in kilobytes; busybox shortens large values to
    /// `12m` or `1.2g`.
    static func parseKilobytes(_ raw: Substring) -> Double? {
        let text = raw.lowercased()
        let scale: Double
        var number = Substring(text)
        switch text.last {
        case "k": scale = 1; number = number.dropLast()
        case "m": scale = 1024; number = number.dropLast()
        case "g": scale = 1024 * 1024; number = number.dropLast()
        default: scale = 1
        }
        return Double(number).map { $0 * scale }
    }
}
