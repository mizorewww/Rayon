//
//  MonitorSession.swift
//  MachineStatusView
//
//  A live monitor of one server: connects over SSH, reads /proc on every refresh
//  and keeps the samples collected while it is open for the sparklines.
//

import Combine
import Foundation
import MachineStatus
import NSRemoteShell
import RayonModule

/// Samples collected by the app while a monitor is open (one per refresh).
public struct MonitorHistory: Equatable {
    public static let capacity = 60

    public private(set) var cpu: [Double] = []
    public private(set) var memory: [Double] = []
    public private(set) var receive: [Double] = []
    public private(set) var transmit: [Double] = []

    public init() {}

    mutating func record(_ status: ServerStatus) {
        Self.push(Double(status.processor.summary.sumUsed), to: &cpu)
        Self.push(status.memoryUsedPercent, to: &memory)
        Self.push(Double(status.totalReceivePerSecond), to: &receive)
        Self.push(Double(status.totalTransmitPerSecond), to: &transmit)
    }

    private static func push(_ value: Double, to list: inout [Double]) {
        list.append(value.isFinite ? value : 0)
        if list.count > capacity { list.removeFirst(list.count - capacity) }
    }
}

public extension ServerStatus {
    var totalReceivePerSecond: Int {
        network.elements.map(\.rxBytesPerSec).reduce(0, &+)
    }

    var totalTransmitPerSecond: Int {
        network.elements.map(\.txBytesPerSec).reduce(0, &+)
    }

    /// kB values from /proc/meminfo.
    var memoryUsedKB: Double {
        Double(max(0, memory.memTotal - memory.memFree - memory.memCached - memory.memBuffers))
    }

    var memoryCacheKB: Double {
        Double(max(0, memory.memCached + memory.memBuffers))
    }

    var memoryUsedPercent: Double {
        guard memory.memTotal > 0 else { return 0 }
        return memoryUsedKB / Double(memory.memTotal) * 100
    }

    var hasData: Bool {
        !system.hostname.isEmpty || memory.memTotal > 0
    }
}

public final class MonitorSession: ObservableObject, Identifiable, Equatable {
    public enum Phase: Equatable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    public let id = UUID()
    public let machine: RDMachine
    let identity: RDIdentity?

    public let status = ServerStatus()
    @Published public private(set) var phase: Phase = .connecting
    @Published public private(set) var history = MonitorHistory()
    @Published public private(set) var lastUpdate: Date?
    @Published public private(set) var isRefreshing = false

    private var shell: NSRemoteShell
    private var loopContinue = true
    private var cancellables = Set<AnyCancellable>()

    private static let queue = DispatchQueue(label: "wiki.qaq.monitor", attributes: .concurrent)

    public init(machine: RDMachine, identity: RDIdentity?) {
        self.machine = machine
        self.identity = identity
        shell = NSRemoteShell.configured(for: machine, timeout: RayonStore.shared.timeoutNumber)
        // Re-publish nested status changes so one observer is enough.
        status.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        MonitorSession.queue.async { [weak self] in
            self?.updateLoop()
        }
    }

    deinit {
        debugPrint("\(self) \(#function) \(machine.id)")
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
            loopContinue = false
            status.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
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
            status.network = .init(elements: [
                .init(device: "eth0", rxBytesPerSec: 2_400_000, txBytesPerSec: 640_000),
                .init(device: "docker0", rxBytesPerSec: 81_000, txBytesPerSec: 96_000),
            ])
            status.fileSystem = .init(elements: [
                .init(mountPoint: "/", size: "98G", used: "41G", free: "52G", percent: 44),
                .init(mountPoint: "/data", size: "1.8T", used: "1.3T", free: "450G", percent: 74),
            ])
            phase = .connected
            for step in 0 ..< 40 {
                status.network = .init(elements: [
                    .init(device: "eth0", rxBytesPerSec: 1_600_000 + (step % 7) * 260_000, txBytesPerSec: 400_000 + (step % 5) * 90_000),
                    .init(device: "docker0", rxBytesPerSec: 81_000, txBytesPerSec: 96_000),
                ])
                history.record(status)
            }
            lastUpdate = Date()
        }
    #endif

    public static func == (lhs: MonitorSession, rhs: MonitorSession) -> Bool {
        lhs.id == rhs.id
    }

    public var refreshInterval: Int {
        max(1, RayonStore.shared.monitorInterval)
    }

    private func updateLoop() {
        var failures = 0
        while loopContinue {
            if !(shell.isConnected && shell.isAuthenticated) {
                onMainThread { if self.phase != .connected { self.phase = .connecting } }
                connectAndAuthenticate()
            }
            guard loopContinue else { break }
            if shell.isConnected, shell.isAuthenticated {
                failures = 0
                onMainThread {
                    self.phase = .connected
                    self.isRefreshing = true
                    var read = RayonStore.shared.machineGroup[self.machine.id]
                    if read.isNotPlaceholder() {
                        read.lastBanner = self.shell.remoteBanner ?? read.lastBanner
                        read.lastConnection = Date()
                        RayonStore.shared.machineGroup[self.machine.id] = read
                    }
                }
                status.requestInfoAndWait(with: shell)
                // The status updates were queued on main; record after them.
                onMainThread {
                    self.history.record(self.status)
                    self.lastUpdate = Date()
                    self.isRefreshing = false
                }
            } else {
                failures += 1
                let message = shell.getLastError() ?? "Unable to connect or authenticate"
                onMainThread { self.phase = .failed(message) }
            }
            let wait = failures > 0 ? min(30, 5 * failures) : refreshInterval
            var slept = 0
            while slept < wait, loopContinue {
                sleep(1)
                slept += 1
            }
        }
        onMainThread { self.phase = .closed }
    }

    private func connectAndAuthenticate() {
        shell.connectAndAuthenticate(
            identity: identity,
            autoIdentities: RayonStore.shared.identityGroupForAutoAuth
        )
    }

    public func shutdown() {
        loopContinue = false
        let shell = shell
        MonitorSession.queue.async {
            shell.requestDisconnectAndWait()
            shell.destroyPermanently()
        }
    }
}

/// Owns the open monitors of the app.
public final class MonitorCenter: ObservableObject {
    nonisolated(unsafe) public static let shared = MonitorCenter()

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

    public func endAll() {
        sessions.forEach { $0.shutdown() }
        sessions = []
    }
}
