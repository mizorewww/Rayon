//
//  BatchSnippetExecContext.swift
//  RayonModule
//
//  Shared batch snippet execution context used by macOS and iOS. Runs on a
//  few servers at a time, each over the server's pooled connection; a run
//  that exits non-zero, or without an exit status, counts as failed. Runs
//  get no terminal, so nothing waits on a prompt; Stop sends the remote
//  process SIGTERM.
//  Uses O(1) UTF-8 byte-ring buffers and publishes state transitions on @MainActor.
//

import Combine
import Foundation
import NIOCore
import RayonSSH
import Logger

public final class BatchSnippetExecContext: ObservableObject, @unchecked Sendable {
    public let snippet: RDSnippet
    public let machines: [RDMachine.ID]
    public let names: [RDMachine.ID: String]

    @Published public private(set) var completedCount: Int = 0
    @Published public private(set) var isRunning: Bool = false

    /// Fires on any thread when a server's output grows.
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

    public init(snippet: RDSnippet, machines: [RDMachine.ID]) {
        self.snippet = snippet
        self.machines = machines
        var buildNames: [RDMachine.ID: String] = [:]
        for machine in machines {
            guard let object = RayonStore.workerMachine(for: machine) else {
                Logger.app.errorFile("snippet run: machine \(machine) is malformed")
                receivedBuffer[machine] = Data("\r\n[*] Malformed Machine Info\r\n".utf8)
                continue
            }
            buildNames[machine] = object.name
        }
        names = buildNames
    }

    private var didStart = false

    public func start() {
        accessLock.lock()
        let shouldStart = !didStart
        didStart = true
        accessLock.unlock()
        guard shouldStart else { return }
        Telemetry.record(.feature(.snippetsRun))
        onMainThread { [weak self] in
            self?.isRunning = true
        }
        let run = Task.detached { await self.runAll() }
        accessLock.withLock { self.batch = run }
    }

    /// How many servers run the snippet at once.
    static let concurrency = 8

    private var batch: Task<Void, Never>?
    private var running: [RDMachine.ID: Task<Void, Never>] = [:]
    private var stopped: Set<RDMachine.ID> = []
    /// The last byte appended per server, to tell a bare \n from \r\n.
    private var lastByte: [RDMachine.ID: UInt8] = [:]
    private var receivedBuffer: [RDMachine.ID: Data] = [:]
    private var completedMachines: [RDMachine.ID] = []
    private var consumedByteCount: [UUID: Int] = [:]
    private var droppedByteCount: [RDMachine.ID: Int] = [:]
    private var startedAt: [RDMachine.ID: Date] = [:]
    private var finishedAt: [RDMachine.ID: Date] = [:]
    private var failedMachines: Set<RDMachine.ID> = []

    public enum MachineState: Equatable {
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
        accessLock.lock()
        defer { accessLock.unlock() }
        guard let start = startedAt[machine] else { return .waiting }
        if let end = finishedAt[machine] {
            let duration = end.timeIntervalSince(start)
            return failedMachines.contains(machine) ? .failed(duration: duration) : .done(duration: duration)
        }
        return .running(since: start)
    }

    /// Asks every running command to stop.
    public func stopAll() {
        let (batch, tasks) = accessLock.withLock {
            stopped.formUnion(machines)
            return (self.batch, Array(running.values))
        }
        batch?.cancel()
        tasks.forEach { $0.cancel() }
    }

    /// Stops a single machine's execution.
    public func stop(machine: RDMachine.ID) {
        let task = accessLock.withLock {
            stopped.insert(machine)
            return running[machine]
        }
        task?.cancel()
    }

    public var safeAccessCompletedMachines: [RDMachine.ID] {
        accessLock.lock()
        defer { accessLock.unlock() }
        return completedMachines
    }

    public var hasFailures: Bool {
        accessLock.lock()
        defer { accessLock.unlock() }
        return !failedMachines.isEmpty
    }

    let accessLock = NSLock()
    func safeAccess(on: () -> Void) {
        accessLock.lock()
        on()
        accessLock.unlock()
    }

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
        onMainThread { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.objectWillChange.send()
        }
    }

    /// Runs on one server in a task of its own, so it can be stopped alone.
    private func runTracked(on machine: RDMachine.ID) async {
        let task = accessLock.withLock { () -> Task<Void, Never>? in
            guard !stopped.contains(machine), !Task.isCancelled else { return nil }
            let task = Task { await self.beginExec(on: machine) }
            running[machine] = task
            return task
        }
        await task?.value
    }

    /// O(1) byte-indexed slice extraction from the per-machine output ring buffer.
    public func requestBuffer(for terminalId: UUID, machine: UUID) -> String {
        accessLock.lock()
        let buffer = receivedBuffer[machine] ?? Data()
        let dropped = droppedByteCount[machine, default: 0]
        let consumed = consumedByteCount[terminalId, default: 0]
        let totalAvailable = dropped + buffer.count
        guard consumed < totalAvailable else {
            accessLock.unlock()
            return ""
        }
        let sliceStart = max(0, consumed - dropped)
        let slice = buffer.dropFirst(sliceStart)
        consumedByteCount[terminalId] = totalAvailable
        accessLock.unlock()
        return String(decoding: slice, as: UTF8.self)
    }

    private static let bufferLimit = 1024 * 1024

    /// Call with accessLock held.
    private func lockedAppendToBuffer(_ output: String, for machine: RDMachine.ID) {
        let utf8 = Data(output.utf8)
        guard !utf8.isEmpty else { return }
        var current = receivedBuffer[machine] ?? Data()
        current.append(utf8)
        if current.count > Self.bufferLimit {
            let excess = current.count - Self.bufferLimit
            current = Data(current.dropFirst(excess))
            droppedByteCount[machine, default: 0] += excess
        }
        receivedBuffer[machine] = current
    }

    private func appendToBuffer(_ output: String, for machine: RDMachine.ID) {
        safeAccess {
            self.lockedAppendToBuffer(output, for: machine)
        }
        outputAppended.send(machine)
    }

    /// Command output as xterm wants it: a bare \n becomes \r\n.
    private func appendOutput(_ chunk: ByteBuffer, for machine: RDMachine.ID) {
        safeAccess {
            var previous = lastByte[machine] ?? 0
            var cleaned = [UInt8]()
            cleaned.reserveCapacity(chunk.readableBytes)
            for byte in chunk.readableBytesView {
                if byte == 0x0A, previous != 0x0D { cleaned.append(0x0D) }
                cleaned.append(byte)
                previous = byte
            }
            lastByte[machine] = previous
            lockedAppendToBuffer(String(decoding: cleaned, as: UTF8.self), for: machine)
        }
        outputAppended.send(machine)
    }

    func beginExec(on machine: RDMachine.ID) async {
        safeAccess { self.startedAt[machine] = Date() }
        onMainThread { [weak self] in self?.objectWillChange.send() }

        let failed: String? = await execute(on: machine)
        let doneCount: Int = accessLock.withLock {
            if let failed {
                lockedAppendToBuffer("\r\n[E] \(failed)\r\n", for: machine)
                failedMachines.insert(machine)
            } else {
                lockedAppendToBuffer("\r\n[*] Execution completed\r\n", for: machine)
            }
            if !completedMachines.contains(machine) {
                completedMachines.append(machine)
            }
            finishedAt[machine] = Date()
            running[machine] = nil
            return completedMachines.count
        }
        outputAppended.send(machine)
        onMainThread { [weak self] in
            guard let self else { return }
            self.completedCount = doneCount
            self.objectWillChange.send()
        }
    }

    /// Runs the snippet; returns why it failed, or nil when it exited 0.
    private func execute(on machine: RDMachine.ID) async -> String? {
        guard let remote = RayonStore.workerMachine(for: machine) else {
            Logger.app.errorFile("snippet run: machine \(machine) vanished mid-run")
            return "The server no longer exists"
        }
        let lease: SSHLease
        do {
            lease = try await SSHConnectionPool.shared.lease(for: remote)
        } catch {
            return error.localizedDescription.replacingOccurrences(of: "\n", with: "\r\n")
        }
        defer { lease.release() }
        appendToBuffer("[*] Execute Begin\r\n", for: machine)
        do {
            let status = try await lease.connection.execute(snippet.code) { [weak self] chunk, _ in
                self?.appendOutput(chunk, for: machine)
            }
            return status == 0 ? nil : "Exited with status \(status)"
        } catch is CancellationError {
            return "Stopped"
        } catch {
            return Task.isCancelled ? "Stopped" : error.localizedDescription
        }
    }
}
