//
//  BatchSnippetExecContext.swift
//  RayonModule
//
//  Shared batch snippet execution context used by macOS and iOS. Runs on a
//  few servers at a time, each over the server's pooled connection; a run
//  that exits non-zero, or without an exit status, counts as failed. Runs
//  get no terminal, so nothing waits on a prompt; Stop sends the remote
//  process SIGTERM.
//  Bookkeeping lives on the main actor; output lands in O(1) UTF-8 byte-ring
//  buffers from the connections' threads.
//

import Combine
import Foundation
import NIOCore
import RayonSSH
import Logger
import Synchronization

@MainActor
public final class BatchSnippetExecContext: ObservableObject {
    public nonisolated let snippet: RDSnippet
    public nonisolated let machines: [RDMachine.ID]
    public nonisolated let names: [RDMachine.ID: String]

    @Published public private(set) var completedCount: Int = 0
    @Published public private(set) var isRunning: Bool = false

    /// Fires when a server's output grows.
    private let outputAppended = PassthroughSubject<RDMachine.ID, Never>()

    /// Once on subscribing, then whenever `machine`'s output grows: at
    /// most every 50 ms and on the main queue, since a chatty command would
    /// otherwise wake the view per chunk.
    public func outputChanges(for machine: RDMachine.ID) -> AnyPublisher<Void, Never> {
        outputAppended
            .filter { $0 == machine }
            .map { _ in }
            .prepend(())
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    /// Each server's output, appended to from the connections' threads.
    private struct Output {
        /// The last byte appended per server, to tell a bare \n from \r\n.
        var lastByte: [RDMachine.ID: UInt8] = [:]
        var received: [RDMachine.ID: Data] = [:]
        var consumedByteCount: [UUID: Int] = [:]
        var droppedByteCount: [RDMachine.ID: Int] = [:]
        /// Servers whose growth the main actor has not announced yet.
        var unannounced: Set<RDMachine.ID> = []

        private static let limit = 1024 * 1024

        mutating func append(_ output: String, for machine: RDMachine.ID) {
            let utf8 = Data(output.utf8)
            guard !utf8.isEmpty else { return }
            var current = received[machine] ?? Data()
            current.append(utf8)
            if current.count > Self.limit {
                let excess = current.count - Self.limit
                current = Data(current.dropFirst(excess))
                droppedByteCount[machine, default: 0] += excess
            }
            received[machine] = current
        }
    }

    private nonisolated let output = Mutex(Output())

    public init(snippet: RDSnippet, machines: [RDMachine.ID]) {
        self.snippet = snippet
        self.machines = machines
        var buildNames: [RDMachine.ID: String] = [:]
        for machine in machines {
            guard let object = RayonStore.workerMachine(for: machine) else {
                Logger.app.errorFile("snippet run: machine \(machine) is malformed")
                output.withLock { $0.received[machine] = Data("\r\n[*] \(String(localized: "Malformed Machine Info", bundle: .module))\r\n".utf8) }
                continue
            }
            buildNames[machine] = object.name
        }
        names = buildNames
    }

    private var didStart = false

    public func start() {
        guard !didStart else { return }
        didStart = true
        Telemetry.record(.feature(.snippetsRun))
        isRunning = true
        batch = Task { await self.runAll() }
    }

    /// How many servers run the snippet at once.
    static let concurrency = 8

    private var batch: Task<Void, Never>?
    private var running: [RDMachine.ID: Task<Void, Never>] = [:]
    private var stopped: Set<RDMachine.ID> = []
    private var completedMachines: [RDMachine.ID] = []
    private var startedAt: [RDMachine.ID: Date] = [:]
    private var finishedAt: [RDMachine.ID: Date] = [:]
    private var failedMachines: Set<RDMachine.ID> = []

    public enum MachineState: Equatable, Sendable {
        case waiting
        case running(since: Date)
        case done(duration: TimeInterval)
        case failed(duration: TimeInterval)

        public var isFinished: Bool {
            switch self {
            case .done, .failed: return true
            case .waiting, .running: return false
            }
        }
    }

    public func state(for machine: RDMachine.ID) -> MachineState {
        guard let start = startedAt[machine] else { return .waiting }
        if let end = finishedAt[machine] {
            let duration = end.timeIntervalSince(start)
            return failedMachines.contains(machine) ? .failed(duration: duration) : .done(duration: duration)
        }
        return .running(since: start)
    }

    /// Asks every running command to stop.
    public func stopAll() {
        stopped.formUnion(machines)
        batch?.cancel()
        running.values.forEach { $0.cancel() }
    }

    /// Stops a single machine's execution.
    public func stop(machine: RDMachine.ID) {
        stopped.insert(machine)
        running[machine]?.cancel()
    }

    public var safeAccessCompletedMachines: [RDMachine.ID] { completedMachines }

    public var hasFailures: Bool { !failedMachines.isEmpty }

    private func runAll() async {
        let targets = machines.filter { names[$0] != nil }
        await withTaskGroup(of: Void.self) { group in
            var pending = targets.makeIterator()
            for _ in 0 ..< Self.concurrency {
                guard let machine = pending.next() else { break }
                group.addTask { await self.runTracked(on: machine) }
            }
            while await group.next() != nil {
                guard let machine = pending.next() else { continue }
                group.addTask { await self.runTracked(on: machine) }
            }
        }
        isRunning = false
        objectWillChange.send()
    }

    /// Runs on one server in a task of its own, so it can be stopped alone.
    private func runTracked(on machine: RDMachine.ID) async {
        guard !stopped.contains(machine), !Task.isCancelled else { return }
        let task = Task { await self.beginExec(on: machine) }
        running[machine] = task
        await task.value
    }

    /// O(1) byte-indexed slice extraction from the per-machine output ring buffer.
    public func requestBuffer(for terminalId: UUID, machine: UUID) -> String {
        let slice: Data? = output.withLock { output in
            let buffer = output.received[machine] ?? Data()
            let dropped = output.droppedByteCount[machine, default: 0]
            let consumed = output.consumedByteCount[terminalId, default: 0]
            let totalAvailable = dropped + buffer.count
            guard consumed < totalAvailable else { return nil }
            output.consumedByteCount[terminalId] = totalAvailable
            return Data(buffer.dropFirst(max(0, consumed - dropped)))
        }
        return slice.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private nonisolated func appendToBuffer(_ text: String, for machine: RDMachine.ID) {
        let announce = output.withLock {
            $0.append(text, for: machine)
            return $0.unannounced.insert(machine).inserted
        }
        if announce { Task { @MainActor in self.announceOutput() } }
    }

    /// One hop to the main actor per burst of output, however many chunks.
    private func announceOutput() {
        let grown = output.withLock { output in
            defer { output.unannounced = [] }
            return output.unannounced
        }
        grown.forEach(outputAppended.send)
    }

    /// Command output as xterm wants it: a bare \n becomes \r\n.
    private nonisolated func appendOutput(_ chunk: ByteBuffer, for machine: RDMachine.ID) {
        let cleaned = output.withLock { output in
            var previous = output.lastByte[machine] ?? 0
            var cleaned = [UInt8]()
            cleaned.reserveCapacity(chunk.readableBytes)
            for byte in chunk.readableBytesView {
                if byte == 0x0A, previous != 0x0D { cleaned.append(0x0D) }
                cleaned.append(byte)
                previous = byte
            }
            output.lastByte[machine] = previous
            return cleaned
        }
        appendToBuffer(String(decoding: cleaned, as: UTF8.self), for: machine)
    }

    func beginExec(on machine: RDMachine.ID) async {
        startedAt[machine] = Date()
        objectWillChange.send()

        let failed: String? = await execute(on: machine)
        if let failed {
            appendToBuffer("\r\n[E] \(failed)\r\n", for: machine)
            failedMachines.insert(machine)
        } else {
            appendToBuffer("\r\n[*] \(String(localized: "Execution completed", bundle: .module))\r\n", for: machine)
        }
        if !completedMachines.contains(machine) {
            completedMachines.append(machine)
        }
        finishedAt[machine] = Date()
        running[machine] = nil
        completedCount = completedMachines.count
        objectWillChange.send()
    }

    /// Runs the snippet; returns why it failed, or nil when it exited 0.
    private func execute(on machine: RDMachine.ID) async -> String? {
        guard let remote = RayonStore.workerMachine(for: machine) else {
            Logger.app.errorFile("snippet run: machine \(machine) vanished mid-run")
            return String(localized: "The server no longer exists", bundle: .module)
        }
        let lease: SSHLease
        do {
            lease = try await SSHConnectionPool.shared.lease(for: remote)
        } catch {
            return error.localizedDescription.replacingOccurrences(of: "\n", with: "\r\n")
        }
        defer { lease.release() }
        appendToBuffer("[*] \(String(localized: "Execute Begin", bundle: .module))\r\n", for: machine)
        do {
            let status = try await lease.connection.execute(snippet.code) { [weak self] chunk, _ in
                self?.appendOutput(chunk, for: machine)
            }
            return status == 0 ? nil : String(localized: "Exited with status \(status)", bundle: .module)
        } catch is CancellationError {
            return String(localized: "Stopped", bundle: .module)
        } catch {
            return Task.isCancelled ? String(localized: "Stopped", bundle: .module) : error.localizedDescription
        }
    }
}
