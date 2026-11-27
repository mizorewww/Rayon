//
//  RemoteDesktopManager.swift
//  RayonModule
//
//  Owns the open remote-desktop sessions, the same way TerminalManager
//  owns terminals and FileTransferManager owns transfers. Views bind to
//  `sessions`; `begin` reuses an existing session for the machine when the
//  protocol matches.
//

import Combine
import Foundation
import Logger

@MainActor
public final class RemoteDesktopManager: ObservableObject {
    public static let shared = RemoteDesktopManager()

    @Published public private(set) var sessions: [RemoteDesktopSession] = []

    private init() {}

    /// Starts a remote desktop on the machine, or returns the session that
    /// is already showing it. `overrideProtocol` lets a caller open VNC on a
    /// machine whose configured protocol is something else (the machine's
    /// stored settings for that protocol still apply). Nil when the machine
    /// is not saved.
    @discardableResult
    public func begin(
        for machineID: RDMachine.ID,
        overrideProtocol: RDMachine.RemoteDesktopProtocolType? = nil
    ) -> RemoteDesktopSession? {
        let store = RayonStore.shared
        guard let machine = store.machine(machineID) else { return nil }
        let type = overrideProtocol ?? machine.remoteDesktopProtocol
        if let existing = sessions.first(where: { $0.machine.id == machineID && $0.protocolType == type }) {
            return existing
        }
        let session = RemoteDesktopSession(machine: machine, protocolType: type)
        sessions.append(session)
        session.connect()
        store.updateMachine(machineID) { $0.lastConnection = Date() }
        return session
    }

    /// The session showing a machine's desktop, if one is open.
    public func session(for machineID: RDMachine.ID) -> RemoteDesktopSession? {
        sessions.first { $0.machine.id == machineID }
    }

    public func session(withID id: UUID) -> RemoteDesktopSession? {
        sessions.first { $0.id == id }
    }

    /// Ends a session: disconnects it and drops it from the list.
    public func end(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        Logger.remoteDesktop.infoFile("end \(session.machine.name)")
        session.disconnect()
        sessions.removeAll { $0.id == id }
    }
}
