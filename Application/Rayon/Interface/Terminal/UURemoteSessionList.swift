//
//  UURemoteSessionList.swift
//  Rayon
//

import Foundation
import RayonModule

/// What a terminal to a UU Remote device starts on: a new session, or one
/// the device kept running.
enum UURemoteSessionChoice {
    case new
    case resume(UInt32)
}

/// The sessions a UU Remote device keeps for its terminals, listed for the
/// pickers that offer to resume one (a sheet on the Mac, a modal on iOS).
@MainActor
final class UURemoteSessionList: ObservableObject {
    enum Phase { case loading, failed(String), loaded }

    let machine: RDMachine
    @Published private(set) var phase = Phase.loading
    @Published private(set) var sessions: [UUTerminalSession] = []
    @Published var selection: UInt32?
    /// How the connection to the device is getting on, while it loads.
    @Published private(set) var status = ""

    init(machine: RDMachine) {
        self.machine = machine
    }

    /// Lists the device's sessions. False when there is none to resume.
    func load() async -> Bool {
        phase = .loading
        let watch = Task { @MainActor in
            while !Task.isCancelled {
                status = UURemoteConnections.shared.status(for: machine)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { watch.cancel() }
        do {
            let available = try await TerminalManager.shared.resumableUUSessions(for: machine)
            if available.isEmpty { return false }
            sessions = available
            if selection.map({ id in !available.contains { $0.id == id } }) ?? true {
                selection = (available.first(where: \.isDetached) ?? available.first)?.id
            }
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
        return true
    }

    /// Ends a session on the device. False once none is left.
    func end(_ session: UUTerminalSession) async -> Bool {
        do {
            try await UURemoteConnections.shared.endSession(session.id, on: machine)
        } catch {
            phase = .failed(error.localizedDescription)
            return true
        }
        sessions.removeAll { $0.id == session.id }
        if selection == session.id { selection = sessions.first?.id }
        return !sessions.isEmpty
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
