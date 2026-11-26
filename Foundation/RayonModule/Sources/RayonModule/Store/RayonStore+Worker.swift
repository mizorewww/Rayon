//
//  RayonStore+Worker.swift
//  RayonModule
//
//  What worker queues read from the store. Every write of the store lands
//  on the main thread (enforced in `storeEncryptedDefault`), and each
//  write mirrors the values a worker may need into `workerState` under
//  the lock, so a worker never touches the main-thread properties: an
//  array read racing a main-thread write would be a torn access.
//

import Foundation
import os

public extension RayonStore {
    /// The mirror of the main-thread values a worker queue may read.
    /// Written only from the main-thread property observers.
    struct WorkerState: Sendable {
        var machines: [RDMachine] = []
        var identities: [RDIdentity] = []
        var timeout: Int = 5
        var monitorInterval: Int = 3
        var terminalFontSize: Int = 14
    }

    /// `timeoutNumber` for a shell built on a worker queue.
    var workerTimeoutNumber: NSNumber {
        workerState.withLock { NSNumber(value: $0.timeout) }
    }

    /// `monitorInterval` for the monitor's worker loop.
    var workerMonitorInterval: Int {
        workerState.withLock { $0.monitorInterval }
    }

    /// `terminalFontSize` for a renderer configured on a worker queue.
    var workerTerminalFontSize: Int {
        workerState.withLock { $0.terminalFontSize }
    }

    /// `machineGroup[id]` from the worker snapshot: the machine, or the
    /// placeholder when it is gone.
    func workerMachine(for id: RDMachine.ID) -> RDMachine {
        workerState.withLock { $0.machines.first(where: { $0.id == id }) ?? .init() }
    }

    /// `associatedIdentity(for:)` from the worker snapshot: nil when the
    /// reference is unset, malformed, or resolves to a placeholder.
    func workerAssociatedIdentity(for machine: RDMachine) -> RDIdentity? {
        guard let raw = machine.associatedIdentity,
              let uuid = UUID(uuidString: raw)
        else { return nil }
        return workerState.withLock { state in
            let identity = state.identities.first(where: { $0.id == uuid }) ?? .init()
            return identity.username.isEmpty ? nil : identity
        }
    }

    /// `identityGroupForAutoAuth` from the worker snapshot.
    var workerIdentitiesForAutoAuth: [RDIdentity] {
        workerState.withLock {
            $0.identities
                .filter(\.authenticAutomatically)
                // make sure not to reopen too many times
                .sorted { $0.username < $1.username }
        }
    }
}
