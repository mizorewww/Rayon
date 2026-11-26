//
//  MonitorSession.swift
//  MachineStatusView
//
//  A live monitor of one server: connects over SSH, samples native system metrics
//  on every refresh and keeps the history for the sparklines.
//

import Foundation
import MachineStatus
import RayonModule
import RayonSSH

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

    public init() {}

    /// Only real readings get here: a failed round publishes nothing, so
    /// it never lands in the history as a zero.
    func recording(_ status: ServerStatus) -> MonitorSnapshot {
        var next = self
        next.status = status
        next.history.record(status)
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
        /// Connected, but the server does not run the status script (no
        /// POSIX shell, as on Windows OpenSSH). Not retried on its own.
        case unavailable
        case failed(String)
        case closed
    }

    public nonisolated let id = UUID()
    /// The server's details the connection was made with; `retarget`
    /// replaces them when they were edited since.
    public private(set) var machine: RDMachine
    private(set) var identity: RDIdentity?

    @Published public private(set) var phase: Phase = .connecting
    @Published public private(set) var snapshot = MonitorSnapshot()

    public var status: ServerStatus { snapshot.status }
    public var history: MonitorHistory { snapshot.history }

    private var updateTask: Task<Void, Never>?

    public init(machine: RDMachine, identity: RDIdentity?) {
        self.machine = machine
        self.identity = identity
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
        max(1, RayonStore.workerMonitorInterval)
    }

    private func setPhase(_ next: Phase) {
        if phase != next { phase = next }
    }

    /// Each round publishes at most one snapshot (plus a phase change when
    /// the connection state moves), so observers redraw once per round.
    /// Samples over the server's pooled connection.
    ///
    /// Every await can outlive a `retarget` or `reconnect`, which cancel
    /// this loop and start another; a cancelled loop stops before it
    /// publishes anything. Its sampler is its own: a cancelled loop's
    /// in-flight sample must not share counters with its successor's.
    private func updateLoop() async {
        let sampler = ServerStatusSampler()
        var failures = 0
        /// Whether this connection produced a reading yet.
        var hasReading = false
        var lease: SSHLease?
        defer { lease?.release() }
        /// Whether a lease was asked for already: the next is a reconnect.
        var reconnecting = false
        while !Task.isCancelled {
            if lease.map({ !$0.connection.isActive }) ?? true {
                lease?.release()
                lease = nil
                if phase != .connected { setPhase(.connecting) }
                // Statics and counters belong to the connection; a reconnect may land
                // on a reimaged or different host.
                sampler.resetConnection()
                hasReading = false
                let background = reconnecting
                reconnecting = true
                do {
                    let leased = try await SSHConnectionPool.shared.lease(for: machine, background: background)
                    lease = leased
                    if Task.isCancelled { break }
                    recordConnection(banner: leased.connection.serverVersion)
                } catch {
                    if Task.isCancelled { break }
                    failures += 1
                    setPhase(.failed(error.localizedDescription))
                }
            }
            if Task.isCancelled { break }
            if let connection = lease?.connection {
                if failures == 0 { setPhase(.connected) }
                let timeout = Duration.seconds(max(10, refreshInterval * 2))
                // Output counts whatever the exit status: a missing tool fails
                // the script's last command, not its other sections.
                let round = await sampler.sample { command in
                    guard let result = try? await connection.execute(command, timeout: timeout) else { return "" }
                    return String(decoding: result.output, as: UTF8.self)
                }
                // A loop replaced by reconnect() or ended by shutdown()
                // must not publish over its successor.
                if Task.isCancelled { break }
                switch round {
                case let .status(status):
                    failures = 0
                    hasReading = true
                    setPhase(.connected)
                    snapshot = snapshot.recording(status)
                case .baseline:
                    failures = 0
                    hasReading = true
                    setPhase(.connected)
                    // Rates need a second reading; take it after a second
                    // instead of a whole interval.
                    try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                    continue
                case .empty:
                    // The lease goes either way; the next round, if any,
                    // takes the pool's connection again, a new one if this
                    // one has dropped.
                    var linkAnswers = connection.isActive
                    // A server that does not answer at all (paused, or a
                    // link that has not noticed it dropped) is out of
                    // reach, not one without a POSIX shell. Asked without
                    // running anything: an account that may not run
                    // commands (internal-sftp, git-shell) answers too.
                    if !hasReading, linkAnswers {
                        linkAnswers = await connection.answers(within: .seconds(10))
                    }
                    lease?.release()
                    lease = nil
                    if Task.isCancelled { return }
                    guard Self.emptyRoundIsDeadLink(hasReading: hasReading, linkAnswers: linkAnswers) else {
                        // Reconnecting would only sign in again (and stamp
                        // the store) every half minute for nothing.
                        setPhase(.unavailable)
                        return
                    }
                    // A dead link would otherwise show its last numbers
                    // as live forever. It fails, and the next round
                    // reconnects.
                    failures += 1
                    setPhase(.failed(hasReading ? "The server stopped answering." : "The server isn't answering."))
                }
            }
            let wait = failures > 0 ? min(30, 5 * failures) : refreshInterval
            // Cancellation from shutdown() lands here right away.
            try? await Task.sleep(nanoseconds: UInt64(wait) * NSEC_PER_SEC)
        }
    }

    /// Whether a round with nothing in it means the link died. A server
    /// that never answered the status script on this connection, but runs
    /// other commands, is reachable and cannot be monitored; one that
    /// answered before, or a link that runs nothing, is out of reach.
    nonisolated static func emptyRoundIsDeadLink(hasReading: Bool, linkAnswers: Bool) -> Bool {
        hasReading || !linkAnswers
    }

    /// Stamps the server's banner and last connection once per connection,
    /// not every round: each write republishes the whole store.
    private func recordConnection(banner: String) {
        guard var read = RayonStore.shared.machine(machine.id) else { return }
        if !banner.isEmpty { read.lastBanner = banner }
        read.lastConnection = Date()
        RayonStore.shared.save(read)
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
    }

    /// Starts over on the server's current details: a new connection, and
    /// no readings from the old one (it may have been another host).
    func retarget(machine: RDMachine, identity: RDIdentity?) {
        self.machine = machine
        self.identity = identity
        snapshot = MonitorSnapshot()
        // The restarted loop leases the pool's connection for the new
        // details; the old loop's lease goes with it.
        reconnect()
    }
}

/// Owns the running monitors of the app: one session per server, shared
/// by its monitor page and anything else watching it (the macOS menu bar),
/// so the server is never polled over two connections. Main thread, like
/// the views and menu bar items that show the sessions.
@MainActor
public final class MonitorCenter: ObservableObject {
    public static let shared = MonitorCenter()

    /// The sessions whose monitor page is open.
    @Published public private(set) var sessions: [MonitorSession] = []

    /// Every running session, page or not.
    private var running: [MonitorSession] = []
    /// Users other than the page, per session.
    private var holds: [MonitorSession.ID: Int] = [:]

    private init() {}

    public enum BeginError: LocalizedError {
        case malformedMachine

        public var errorDescription: String? {
            switch self {
            case .malformedMachine: return "This server's details could not be read."
            }
        }
    }

    /// The server's session while its monitor page is open.
    public func session(for machine: RDMachine.ID) -> MonitorSession? {
        sessions.first { $0.machine.id == machine }
    }

    public func session(withID id: MonitorSession.ID) -> MonitorSession? {
        sessions.first { $0.id == id }
    }

    /// Opens the server's monitor page, on its running session if it has one.
    @discardableResult
    public func begin(for machineID: RDMachine.ID) throws -> MonitorSession {
        let session = try runningSession(for: machineID)
        if !sessions.contains(session) { sessions.append(session) }
        RayonStore.shared.storeRecentIfNeeded(from: machineID)
        return session
    }

    /// Closes the monitor page; the session keeps running while held.
    public func end(_ id: MonitorSession.ID) {
        sessions.removeAll { $0.id == id }
        stopIfUnused(id)
    }

    /// Keeps the server's session running without opening its page. Pair
    /// every hold with a `release`.
    public func hold(_ machineID: RDMachine.ID) throws -> MonitorSession {
        let session = try runningSession(for: machineID)
        holds[session.id, default: 0] += 1
        return session
    }

    public func release(_ session: MonitorSession) {
        guard running.contains(session) else {
            // Not ours (a debug preview): nobody else can be using it.
            session.shutdown()
            return
        }
        if let count = holds[session.id], count > 1 {
            holds[session.id] = count - 1
        } else {
            holds[session.id] = nil
        }
        stopIfUnused(session.id)
    }

    /// The server's running session, pointed at its current details: one
    /// started before the server or its identity was edited reconnects
    /// with the new ones, so whoever holds it sees the change too.
    private func runningSession(for machineID: RDMachine.ID) throws -> MonitorSession {
        guard let machine = RayonStore.shared.machine(machineID) else { throw BeginError.malformedMachine }
        let identity = RayonStore.shared.associatedIdentity(for: machine)
        if let existing = running.first(where: { $0.machine.id == machineID }) {
            if Self.connectsDifferently(existing.machine, existing.identity, machine, identity) {
                existing.retarget(machine: machine, identity: identity)
            }
            return existing
        }
        let session = MonitorSession(machine: machine, identity: identity)
        running.append(session)
        return session
    }

    /// Whether the new details reach the server differently: only what
    /// the SSH connection reads counts, so editing anything else (name,
    /// remote desktop settings, written-back state) keeps the session.
    static func connectsDifferently(_ machine: RDMachine, _ identity: RDIdentity?, _ newMachine: RDMachine, _ newIdentity: RDIdentity?) -> Bool {
        ConnectionKey(machine, identity) != ConnectionKey(newMachine, newIdentity)
    }

    /// What `RDMachine.connectSSH` reads to reach and sign in to the server.
    private struct ConnectionKey: Equatable {
        let address: String
        let port: String
        let sshUsername: String
        let associatedIdentity: RDIdentity.ID?
        let transport: RDMachine.Transport
        let cloudflareServiceTokenID: String
        let cloudflareServiceTokenSecret: String
        /// What the UU Remote transport tunnels to.
        let uuTarget: [String]
        let proxyJumpMachineID: RDMachine.ID?
        let identityID: RDIdentity.ID?
        let identityUsername: String?
        let password: String?
        let privateKey: String?
        let publicKey: String?
        let useSSHAgent: Bool?

        init(_ machine: RDMachine, _ identity: RDIdentity?) {
            address = machine.remoteAddress
            port = machine.remotePort
            sshUsername = machine.sshUsername
            associatedIdentity = machine.associatedIdentity
            transport = machine.transport
            cloudflareServiceTokenID = machine.cloudflareServiceTokenID
            cloudflareServiceTokenSecret = machine.cloudflareServiceTokenSecret
            uuTarget = [machine.uuDeviceID, machine.uuAssistID, machine.uuAssistCode]
            proxyJumpMachineID = machine.proxyJumpMachineID
            identityID = identity?.id
            identityUsername = identity?.username
            password = identity?.password
            privateKey = identity?.privateKey
            publicKey = identity?.publicKey
            useSSHAgent = identity?.useSSHAgent
        }
    }

    private func stopIfUnused(_ id: MonitorSession.ID) {
        guard holds[id] == nil,
              !sessions.contains(where: { $0.id == id }),
              let index = running.firstIndex(where: { $0.id == id })
        else {
            return
        }
        running.remove(at: index).shutdown()
    }
}
