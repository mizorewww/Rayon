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
import RayonSSH
import Logger

/// The session's state lives on the main actor; each round awaits the
/// connection and the forward off it.
@MainActor
public class PortForwardContext: ObservableObject, Identifiable {
    public nonisolated let id = UUID()
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
        case portInUse = "port in use"
        case terminating = "terminating"
        case terminated = "terminated"
    }

    /// Views observe the backend's per-forward record fed by the handler
    /// below, not this directly.
    @Published public private(set) var lifecycle: Lifecycle = .awaitingConnect

    /// Lifecycle sink for the owning backend.
    public var lifecycleHandler: ((Lifecycle) -> Void)?

    /// Called once after the lifecycle exits, so the backend can drop the
    /// context and the switch goes back off.
    public var terminationHandler: ((PortForwardContext) -> Void)?

    /// Backoff before reconnecting after a round ends on its own.
    public var reconnectDelay: TimeInterval = 3

    private var task: Task<Void, Never>?

    public init(info: RDPortForward, machine: RDMachine) {
        self.info = info
        self.machine = machine
    }

    func putLifecycle(_ state: Lifecycle) {
        lifecycle = state
        lifecycleHandler?(state)
    }

    /// Starts the lifecycle and returns immediately.
    public func begin() {
        guard task == nil else { return }
        task = Task { await self.runLifecycle() }
    }

    /// Stops the session: a running round is cut off and a pending
    /// reconnect returns at once.
    public func terminate() {
        task?.cancel()
    }

    public var closed: Bool {
        task?.isCancelled ?? false
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
        terminationHandler?(self)
    }

    /// One connection running the forward until it drops or is cancelled.
    /// Signs in as the terminal and the files do: with the server's own
    /// identity, else with the automatic ones. A forward that listens on
    /// this side listens first, so a port in use costs no sign-in.
    private func runRound(reconnecting: Bool) async {
        let listener: SSHForwardListener?
        do {
            switch info.forwardOrientation {
            case .listenRemote:
                listener = nil
            case .listenLocal:
                listener = try await .local(port: info.bindPort, targetHost: info.targetHost, targetPort: info.targetPort)
            case .dynamicSOCKS:
                listener = try await .dynamic(port: info.bindPort)
            }
        } catch SSHError.portInUse {
            putLifecycle(.portInUse)
            return
        } catch {
            Logger.network.infoFile("port forward \(info.id) could not listen: \(error)")
            putLifecycle(.forwardStopped)
            return
        }
        // Only now: a port still in use keeps saying so between retries.
        putLifecycle(.awaitingConnect)
        let lease: SSHLease
        do {
            lease = try await SSHConnectionPool.shared.lease(for: machine, background: reconnecting)
        } catch {
            await listener?.close()
            let failure = error as? RDMachine.SSHFailure
            putLifecycle(failure?.unreachable == false ? .failedAuthenticate : .failedConnect)
            return
        }
        defer { lease.release() }
        putLifecycle(.openingChannel)
        let connection = lease.connection
        do {
            if let listener {
                putLifecycle(.forwardRunning)
                try await connection.runForward(listener)
            } else {
                try await connection.runRemoteForward(
                    bindPort: info.bindPort, targetHost: info.targetHost, targetPort: info.targetPort
                ) { [weak self] in
                    Task { @MainActor in self?.putLifecycle(.forwardRunning) }
                }
            }
        } catch {
            Logger.network.infoFile("port forward \(info.id) ended: \(error)")
        }
        putLifecycle(.forwardStopped)
    }
}
