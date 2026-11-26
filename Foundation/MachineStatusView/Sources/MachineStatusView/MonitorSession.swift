//
//  MonitorSession.swift
//  MachineStatusView
//
//  A live monitor of one server: connects over SSH, samples native system metrics
//  on every refresh and keeps the history for the sparklines.
//

import Foundation
import MachineStatus
import NSRemoteShell
import RayonModule

/// Throughput samples collected while a monitor is open, one per round.
public struct MonitorHistory: Equatable, Sendable {
    public static let capacity = 60

    public private(set) var receive: [Double] = []
    public private(set) var transmit: [Double] = []

    public init() {}

    mutating func record(_ status: ServerStatus) {
        // No interface at all means the network section did not come
        // back; that is a gap, not zero traffic.
        guard !status.network.elements.isEmpty else { return }
        Self.push(Double(status.totalReceivePerSecond), to: &receive)
        Self.push(Double(status.totalTransmitPerSecond), to: &transmit)
    }

    private static func push(_ value: Double, to list: inout [Double]) {
        guard value.isFinite else { return }
        list.append(value)
        if list.count > capacity { list.removeFirst(list.count - capacity) }
    }
}

/// Everything a monitor shows, replaced as a whole once per round so the
/// views observing a session redraw once per round.
public struct MonitorSnapshot: Equatable, Sendable {
    public private(set) var status = ServerStatus()
    public private(set) var history = MonitorHistory()
    public private(set) var date: Date?

    public init() {}

    /// Only real readings get here: a failed round publishes nothing, so
    /// it never lands in the history as a zero.
    func recording(_ status: ServerStatus, at date: Date = Date()) -> MonitorSnapshot {
        var next = self
        next.status = status
        next.history.record(status)
        next.date = date
        return next
    }
}

public extension ServerStatus {
    var totalReceivePerSecond: Int {
        network.elements.map(\.rxBytesPerSec).reduce(0, &+)
    }

    var totalTransmitPerSecond: Int {
        network.elements.map(\.txBytesPerSec).reduce(0, &+)
    }

    /// Memory readings are stored in kB (1024-byte blocks) on every platform.
    var memoryUsedKB: Double {
        if let available = memory.memAvailable, available > 0, available <= memory.memTotal {
            return Double(max(0, memory.memTotal - available))
        }
        return Double(max(0, memory.memTotal - memory.memFree - memory.memCached - memory.memBuffers))
    }

    var memoryCacheKB: Double {
        Double(max(0, memory.memCached + memory.memBuffers))
    }

    var memoryUsedPercent: Double {
        guard memory.memTotal > 0 else { return 0 }
        return memory.phyUsed * 100
    }

    var hasData: Bool {
        !system.hostname.isEmpty || memory.memTotal > 0
    }
}

@MainActor
public final class MonitorSession: ObservableObject, Identifiable, Equatable {
    public enum Phase: Equatable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    public nonisolated let id = UUID()
    public let machine: RDMachine
    let identity: RDIdentity?

    @Published public private(set) var phase: Phase = .connecting
    @Published public private(set) var snapshot = MonitorSnapshot()

    public var status: ServerStatus { snapshot.status }
    public var history: MonitorHistory { snapshot.history }

    private let shell: NSRemoteShell
    private let sampler = ServerStatusSampler()
    private var updateTask: Task<Void, Never>?

    private nonisolated static let queue = DispatchQueue(label: "me.mizorewww.monitor", attributes: .concurrent)

    public init(machine: RDMachine, identity: RDIdentity?) {
        self.machine = machine
        self.identity = identity
        shell = NSRemoteShell.configured(for: machine, timeout: RayonStore.shared.timeoutNumber)
        updateTask = Task { [weak self] in
            await self?.updateLoop()
        }
    }

    #if DEBUG
        /// A session filled with sample readings that never connects, for checking
        /// layouts (menu bar popover, monitor page) without a server.
        public static func preview(machine: RDMachine) -> MonitorSession {
            MonitorSession(previewing: machine)
        }

        private init(previewing machine: RDMachine) {
            self.machine = machine
            identity = nil
            shell = NSRemoteShell()
            var status = ServerStatus()
            let core = ServerStatus.ProcessPercentInfo(system: 6.2, user: 18.4, iowait: 1.1, nice: 0.3, sum: 26)
            var cores: [String: ServerStatus.ProcessPercentInfo] = [:]
            for index in 0 ..< 8 {
                let used = Float(13 + index * 6)
                cores["cpu\(index)"] = ServerStatus.ProcessPercentInfo(system: 4, user: used - 5, iowait: 1, nice: 0, sum: used)
            }
            status.processor = ServerStatus.ProcessorInfo(summary: core, cores: cores)
            status.memory = .init(total: 16_384_000, free: 3_100_000, buffers: 420_000, cached: 5_200_000, swapTotal: 4_096_000, swapFree: 3_500_000)
            status.system = .init(release: "Ubuntu 24.04.1 LTS", uptimeInSec: 1_728_000, hostname: "web-01",
                                  runningProcs: 3, totalProcs: 412, load1: 0.82, load5: 0.64, load15: 0.51)
            status.fileSystem = .init(elements: [
                .init(mountPoint: "/", size: "98G", used: "41G", free: "52G", percent: 44),
                .init(mountPoint: "/data", size: "1.8T", used: "1.3T", free: "450G", percent: 74),
            ])
            let processes: [ServerStatus.TopProcess] = [
                .init(pid: 2214, user: "postgres", command: "postgres", cpuPercent: 38.2, memoryPercent: 6.1, residentKB: 1_002_400),
                .init(pid: 1873, user: "www-data", command: "nginx", cpuPercent: 12.6, memoryPercent: 0.4, residentKB: 64_200),
                .init(pid: 3302, user: "app", command: "node", cpuPercent: 9.8, memoryPercent: 3.2, residentKB: 524_800),
                .init(pid: 912, user: "root", command: "dockerd", cpuPercent: 2.1, memoryPercent: 0.9, residentKB: 148_000),
                .init(pid: 1, user: "root", command: "systemd", cpuPercent: 0.1, memoryPercent: 0.1, residentKB: 12_900),
            ]
            status.processes = .init(
                byCPU: processes,
                byMemory: processes.sorted { ($0.residentKB ?? 0) > ($1.residentKB ?? 0) }
            )
            var snapshot = MonitorSnapshot()
            for step in 0 ..< 40 {
                status.network = .init(elements: [
                    .init(device: "eth0", rxBytesPerSec: 1_600_000 + (step % 7) * 260_000, txBytesPerSec: 400_000 + (step % 5) * 90_000),
                    .init(device: "docker0", rxBytesPerSec: 81000, txBytesPerSec: 96000),
                ])
                snapshot = snapshot.recording(status)
            }
            self.snapshot = snapshot
            phase = .connected
        }
    #endif

    public nonisolated static func == (lhs: MonitorSession, rhs: MonitorSession) -> Bool {
        lhs.id == rhs.id
    }

    private var refreshInterval: Int {
        max(1, RayonStore.shared.workerMonitorInterval)
    }

    private func setPhase(_ next: Phase) {
        if phase != next { phase = next }
    }

    /// Each round publishes at most one snapshot (plus a phase change when
    /// the connection state moves), so observers redraw once per round.
    private func updateLoop() async {
        let shell = shell
        let sampler = sampler
        var failures = 0
        while !Task.isCancelled {
            if !(await Self.blocking { shell.isConnected && shell.isAuthenticated }) {
                if phase != .connected { setPhase(.connecting) }
                let identity = identity
                let username = machine.sshUsernameOverride
                let connected = await Self.blocking {
                    // Statics and counters belong to the connection; a reconnect may land
                    // on a reimaged or different host.
                    sampler.resetConnection()
                    shell.connectAndAuthenticate(
                        identity: identity,
                        autoIdentities: RayonStore.shared.workerIdentitiesForAutoAuth,
                        username: username
                    )
                    return shell.isConnected && shell.isAuthenticated
                }
                if connected { recordConnection() }
            }
            if Task.isCancelled { break }
            if await Self.blocking({ shell.isConnected && shell.isAuthenticated }) {
                failures = 0
                setPhase(.connected)
                let timeout = max(10, Double(refreshInterval * 2))
                let round = await Self.blocking { sampler.sample(with: shell, timeout: timeout) }
                // A loop replaced by reconnect() or ended by shutdown()
                // must not publish over its successor.
                if Task.isCancelled { break }
                switch round {
                case let .status(status):
                    snapshot = snapshot.recording(status)
                case .baseline:
                    // Rates need a second reading; take it after a second
                    // instead of a whole interval.
                    try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                    continue
                case .empty:
                    break
                }
            } else {
                failures += 1
                let message = await Self.blocking {
                    shell.connectFailureReason ?? shell.getLastError() ?? "Unable to connect or authenticate"
                }
                if Task.isCancelled { break }
                setPhase(.failed(message))
            }
            let wait = failures > 0 ? min(30, 5 * failures) : refreshInterval
            // Cancellation from shutdown() lands here right away.
            try? await Task.sleep(nanoseconds: UInt64(wait) * NSEC_PER_SEC)
        }
    }

    /// Stamps the server's banner and last connection once per connection,
    /// not every round: each write republishes the whole store.
    private func recordConnection() {
        var read = RayonStore.shared.machineGroup[machine.id]
        guard read.isNotPlaceholder() else { return }
        read.lastBanner = shell.remoteBanner ?? read.lastBanner
        read.lastConnection = Date()
        RayonStore.shared.machineGroup[machine.id] = read
    }

    /// The SSH API blocks; run it on the monitor queue so the loop's task
    /// suspends at the await instead of blocking a cooperative-pool thread
    /// or the main thread for the whole round.
    private nonisolated static func blocking<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    public func reconnect() {
        updateTask?.cancel()
        phase = .connecting
        updateTask = Task { [weak self] in
            await self?.updateLoop()
        }
    }

    public func shutdown() {
        updateTask?.cancel()
        phase = .closed
        let shell = shell
        MonitorSession.queue.async {
            shell.requestDisconnectAndWait()
            shell.destroyPermanently()
        }
    }
}

/// Owns the open monitors of the app. Main thread, like the views and
/// menu bar items that show the sessions.
@MainActor
public final class MonitorCenter: ObservableObject {
    public static let shared = MonitorCenter()

    @Published public private(set) var sessions: [MonitorSession] = []

    private init() {}

    public enum BeginError: LocalizedError {
        case malformedMachine

        public var errorDescription: String? {
            switch self {
            case .malformedMachine: return "This server's details could not be read."
            }
        }
    }

    public func session(for machine: RDMachine.ID) -> MonitorSession? {
        sessions.first { $0.machine.id == machine }
    }

    public func session(withID id: MonitorSession.ID) -> MonitorSession? {
        sessions.first { $0.id == id }
    }

    /// Returns the running monitor for the server, or starts one.
    @discardableResult
    public func begin(for machineID: RDMachine.ID) throws -> MonitorSession {
        if let existing = session(for: machineID) { return existing }
        let machine = RayonStore.shared.machineGroup[machineID]
        guard machine.isNotPlaceholder() else { throw BeginError.malformedMachine }
        let session = MonitorSession(machine: machine, identity: RayonStore.shared.associatedIdentity(for: machine))
        sessions.append(session)
        RayonStore.shared.storeRecentIfNeeded(from: machineID)
        return session
    }

    public func end(_ id: MonitorSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: index)
        session.shutdown()
    }

}
