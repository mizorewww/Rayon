//
//  ServerStatusSampler.swift
//  MachineStatus
//

import Foundation
import NSRemoteShell

/// Hands a value out of a @Sendable dispatch block without capturing a
/// var, which Swift 6 diagnoses.
private final class ConcurrentValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func store(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Reads rounds of `ServerStatus` from one connection. Rates (CPU,
/// network) are the difference between this round's counters and the
/// previous round's, so the server never sleeps for a sample. Call
/// `resetConnection` after a reconnect. Not thread-safe: one monitor loop
/// owns it and calls it serially.
public final class ServerStatusSampler {
    public enum Round: Equatable, Sendable {
        /// A complete reading.
        case status(ServerStatus)
        /// The first counters of a connection: nothing to difference yet.
        /// Sample again shortly.
        case baseline
        /// Nothing came back (a dropped connection, a killed channel).
        case empty
    }

    private enum CPUCounters {
        case linux(ProcParsers.ProcStat)
        case darwin(times: [Int: ProcParsers.DarwinCPUTime], cpuCount: Int)
    }

    private struct Counters {
        var cpu: CPUCounters?
        var network: [String: ProcParsers.NetworkCounters]
        /// Linux /proc/uptime; zero where the server has no such clock.
        var serverClock: Double
        var clientClock: TimeInterval
    }

    private static let queue = DispatchQueue(label: "me.mizorewww.rayon.info", attributes: .concurrent)

    /// Hostname and os-release, read once per connection.
    private var sessionHostname: String?
    private var sessionReleaseName: String?
    private var previous: Counters?
    /// Off once the server has shown it has no `nvidia-smi` (or is a Mac),
    /// so most servers stop paying for a second channel every round.
    private(set) var probesGraphics = true

    public init() {}

    /// Forgets everything tied to the connection: the statics and the
    /// counter baseline. A reconnect may land on a reimaged or different
    /// host.
    public func resetConnection() {
        sessionHostname = nil
        sessionReleaseName = nil
        previous = nil
        probesGraphics = true
    }

    /// Runs the merged monitor script and the GPU probe on two channels,
    /// then parses every section on its own: one section going missing
    /// (a hung `nvidia-smi`, an unsupported system probe) empties only its
    /// model. `timeout` bounds each channel so a hung probe cannot freeze
    /// the monitor loop forever. Blocks.
    public func sample(with remote: NSRemoteShell, timeout: Double) -> Round {
        // The shell multiplexes channels internally; claiming it Sendable
        // is for the compiler, like the legacy model callbacks.
        nonisolated(unsafe) let remote = remote
        let includeStatic = sessionHostname == nil || sessionReleaseName == nil
        let group = DispatchGroup()
        let queue = Self.queue

        let mergedOutput = ConcurrentValue("")
        group.enter()
        queue.async {
            defer { group.leave() }
            mergedOutput.store(ServerStatus.downloadResultFrom(shell: remote, command: ServerStatus.monitorCommand(includeStatic: includeStatic), timeout: timeout))
        }

        let graphicsOutput = ConcurrentValue<String?>(nil)
        if probesGraphics {
            group.enter()
            queue.async {
                defer { group.leave() }
                graphicsOutput.store(ServerStatus.downloadResultFrom(shell: remote, command: ServerStatus.graphicsCommand, timeout: timeout))
            }
        }

        group.wait()
        return read(mergedOutput.load(), graphicsOutput: graphicsOutput.load(), clientClock: ProcessInfo.processInfo.systemUptime)
    }

    /// Turns one run of the monitor script (and of the GPU probe, when it
    /// ran) into a round. `clientClock` is a monotonic time of arrival,
    /// the fallback clock for rates.
    func read(_ output: String, graphicsOutput: String?, clientClock: TimeInterval) -> Round {
        let includeStatic = sessionHostname == nil || sessionReleaseName == nil
        let sections = ProcParsers.splitMonitorSections(output)
        guard let platform = sections["platform"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !platform.isEmpty
        else {
            return .empty
        }
        let isDarwin = platform == "Darwin"
        if isDarwin || graphicsOutput?.contains(ServerStatus.noGraphicsMarker) == true {
            probesGraphics = false
        }
        if includeStatic {
            // Only a non-empty reading is cached; a failed probe is retried
            // on the next round instead of sticking a placeholder.
            let hostname = (sections["hostname"] ?? "").replacingOccurrences(of: "\n", with: "")
            let releasePayload = (sections["os-release"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !hostname.isEmpty { sessionHostname = hostname }
            if !releasePayload.isEmpty {
                sessionReleaseName = isDarwin
                    ? ProcParsers.parseDarwinReleaseName(releasePayload)
                    : ProcParsers.parseOsReleaseName(releasePayload)
            }
        }

        var status = ServerStatus()
        var load = ServerStatus.SystemLoadInternal()
        let uptime: Double
        let counters: Counters
        if isDarwin {
            let processes = ProcParsers.parseDarwinProcessTimes(sections["cpu"] ?? "")
            let cpuCount = Int((sections["ncpu"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            counters = Counters(
                cpu: processes.times.isEmpty || cpuCount <= 0 ? nil : .darwin(times: processes.times, cpuCount: cpuCount),
                network: ProcParsers.parseDarwinNetstat(sections["net"] ?? ""),
                serverClock: 0,
                clientClock: clientClock
            )
            status.memory = ServerStatus.MemoryInfo(darwinMemory: sections["mem"] ?? "")
            if let average = ProcParsers.parseDarwinLoadavg(sections["loadavg"] ?? "") {
                load.load1avg = average.load1
                load.load5avg = average.load5
                load.load15avg = average.load15
                load.runningProcess = processes.running
                load.totalProcess = processes.times.count
            }
            uptime = ProcParsers.parseDarwinUptime(sections["uptime"] ?? "")
        } else {
            let stat = ProcParsers.parseProcStat(sections["cpu"] ?? "")
            uptime = ProcParsers.parseUptime(sections["uptime"] ?? "")
            counters = Counters(
                cpu: stat.summary == nil ? nil : .linux(stat),
                network: ProcParsers.parseNetDev(sections["net"] ?? ""),
                serverClock: uptime,
                clientClock: clientClock
            )
            status.memory = ServerStatus.MemoryInfo(meminfo: sections["mem"] ?? "")
            load = ProcParsers.parseLoadavg(sections["loadavg"] ?? "")
        }

        guard let previous else {
            self.previous = counters
            return .baseline
        }
        self.previous = counters
        // The server's own clock when it has one: it was read next to the
        // counters, where the client's also carries the network's jitter.
        let elapsed = counters.serverClock > previous.serverClock && previous.serverClock > 0
            ? counters.serverClock - previous.serverClock
            : counters.clientClock - previous.clientClock
        guard elapsed > 0 else { return .baseline }

        switch (previous.cpu, counters.cpu) {
        case let (.linux(before)?, .linux(after)?):
            status.processor = ServerStatus.ProcessorInfo(before: before, after: after) ?? .init()
        case let (.darwin(before, _)?, .darwin(after, cpuCount)?):
            let summary = ProcParsers.darwinCPUPercent(before: before, after: after, interval: elapsed, cpuCount: cpuCount)
            status.processor = ServerStatus.ProcessorInfo(summary: summary, cores: [:])
        default:
            break
        }
        status.network = ServerStatus.NetworkInfo(before: previous.network, after: counters.network, interval: elapsed)
        status.fileSystem = ServerStatus.FileSystemInfo(dfPk: sections["df"] ?? "")
        status.processes = ServerStatus.TopProcessesInfo(cpuSection: sections["procs-cpu"] ?? "", memorySection: sections["procs-mem"] ?? "")
        status.system = ServerStatus.SystemInfo(
            release: sessionReleaseName ?? "",
            uptimeInSec: uptime,
            hostname: sessionHostname ?? "",
            runningProcs: load.runningProcess,
            totalProcs: load.totalProcess,
            load1: load.load1avg,
            load5: load.load5avg,
            load15: load.load15avg
        )
        status.graphics = graphicsOutput.flatMap(ServerStatus.GraphicsInfo.parseCSV)
        return .status(status)
    }
}
