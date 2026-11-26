//
//  PortForwardContext.swift
//  RayonModule
//
//  Shared port-forward session, previously duplicated between the macOS
//  and iOS apps. A round is one connection running the forward; when it
//  drops the round ends and, after a pause, another begins. Terminating
//  cancels the running task.
//

import Foundation
import os
import RayonSSH

public class PortForwardContext: ObservableObject, Identifiable, @unchecked Sendable {
    public var id = UUID()
    public let info: RDPortForward
    public let machine: RDMachine

    /// Where the session is in its connect → forward → stop cycle. Views
    /// match on this instead of the former hint strings, so a copy edit
    /// cannot silently drop a state onto a default branch; the raw values
    /// keep the former hint text for logs.
    public enum Lifecycle: String, CaseIterable, Sendable {
        case awaitingConnect = "awaiting connect"
        case openingChannel = "opening channel"
        case forwardRunning = "forward running"
        case forwardStopped = "forward stopped"
        case failedConnect = "failed connect"
        case failedAuthenticate = "failed authenticate"
        case terminating = "terminating"
        case terminated = "terminated"
    }

    /// Written from the lifecycle thread; views observe the backend's
    /// per-forward record fed by the handler below, not this directly.
    @Published public private(set) var lifecycle: Lifecycle = .awaitingConnect

    /// Lifecycle sink for the owning backend, called from the lifecycle thread.
    public var lifecycleHandler: ((Lifecycle) -> Void)?

    /// Called once on the main thread after the lifecycle exits, so the
    /// backend can drop the context and the switch goes back off.
    public var terminationHandler: ((PortForwardContext) -> Void)?

    /// Backoff before reconnecting after a round ends on its own.
    public var reconnectDelay: TimeInterval = 3

    private let task = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    public init(info: RDPortForward, machine: RDMachine) {
        self.info = info
        self.machine = machine
    }

    func putLifecycle(_ state: Lifecycle) {
        onMainThread { [weak self] in
            self?.lifecycle = state
        }
        lifecycleHandler?(state)
    }

    /// Starts the lifecycle in the background and returns immediately.
    public func begin() {
        task.withLock { task in
            guard task == nil else { return }
            task = Task.detached { await self.runLifecycle() }
        }
    }

    /// Stops the session: a running round is cut off and a pending
    /// reconnect returns at once.
    public func terminate() {
        task.withLock { $0 }?.cancel()
    }

    public var closed: Bool {
        task.withLock { $0?.isCancelled ?? false }
    }

    private func runLifecycle() async {
        var reconnecting = false
        while !Task.isCancelled {
            await runRound(reconnecting: reconnecting)
            reconnecting = true
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(reconnectDelay))
        }
        putLifecycle(.terminated)
        let handler = terminationHandler
        onMainThread { handler?(self) }
    }

    /// One connection running the forward until it drops or is cancelled.
    /// Signs in as the terminal and the files do: with the server's own
    /// identity, else with the automatic ones.
    private func runRound(reconnecting: Bool) async {
        putLifecycle(.awaitingConnect)
        let lease: SSHLease
        do {
            lease = try await SSHConnectionPool.shared.lease(for: machine, background: reconnecting)
        } catch let failure as RDMachine.SSHFailure {
            putLifecycle(failure.unreachable ? .failedConnect : .failedAuthenticate)
            return
        } catch {
            putLifecycle(.failedConnect)
            return
        }
        defer { lease.release() }
        putLifecycle(.openingChannel)
        let connection = lease.connection
        let running: @Sendable () -> Void = { [weak self] in self?.putLifecycle(.forwardRunning) }
        do {
            switch info.forwardOrientation {
            case .listenRemote:
                try await connection.runRemoteForward(
                    bindPort: info.bindPort, targetHost: info.targetHost, targetPort: info.targetPort, onListening: running
                )
            case .listenLocal:
                try await connection.runLocalForward(
                    bindPort: info.bindPort, targetHost: info.targetHost, targetPort: info.targetPort, onListening: running
                )
            case .dynamicSOCKS:
                try await connection.runDynamicForward(bindPort: info.bindPort, onListening: running)
            }
        } catch {
            debugPrint("port forward \(info.id) ended: \(error.localizedDescription)")
        }
        putLifecycle(.forwardStopped)
    }
}
