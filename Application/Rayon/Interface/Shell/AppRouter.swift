//
//  AppRouter.swift
//  Rayon (macOS)
//
//  The main window's navigation state and the actions that open sessions.
//

import Combine
import MachineStatusView
import RayonModule
import SwiftUI

enum Route: Hashable {
    case home
    case servers
    case identities
    case snippets
    case portForward
    case settings
    case terminal(UUID)
    case monitor(UUID)
    case transfer(UUID)
}

final class AppRouter: ObservableObject {
    nonisolated(unsafe) static let shared = AppRouter()

    @Published var route: Route = .home
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    /// Presents the server editor for a new server from anywhere (menu, Home, Servers).
    @Published var presentNewServer = false
    /// Settings category to show when Settings opens.
    @Published var settingsSelection: String = SettingsCategory.general

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // When a session closes, leave its page.
        TerminalManager.shared.$sessionContexts
            .sink { [weak self] contexts in
                guard let self, case let .terminal(id) = self.route else { return }
                if !contexts.contains(where: { $0.id == id }) { self.route = .home }
            }
            .store(in: &cancellables)
        MonitorCenter.shared.$sessions
            .sink { [weak self] sessions in
                guard let self, case let .monitor(id) = self.route else { return }
                if !sessions.contains(where: { $0.id == id }) { self.route = .servers }
            }
            .store(in: &cancellables)
        FileTransferManager.shared.$transfers
            .sink { [weak self] transfers in
                guard let self, case let .transfer(id) = self.route else { return }
                if !transfers.contains(where: { $0.id == id }) { self.route = .home }
            }
            .store(in: &cancellables)
    }

    private var opensAutomatically: Bool {
        RayonStore.shared.openInterfaceAutomatically
    }

    // MARK: - Session actions

    func openTerminal(machine: RDMachine.ID) {
        TerminalManager.shared.createSession(withMachineID: machine) { [weak self] context in
            guard let self, self.opensAutomatically else { return }
            self.route = .terminal(context.id)
        }
    }

    func openTerminal(command: SSHCommandReader) {
        let context = TerminalManager.shared.createSession(withCommand: command)
        if opensAutomatically { route = .terminal(context.id) }
    }

    func openMonitor(machine: RDMachine.ID) {
        do {
            let session = try MonitorCenter.shared.begin(for: machine)
            route = .monitor(session.id)
        } catch {
            UIBridge.presentError(with: error.localizedDescription)
        }
    }

    func openFileTransfer(machine: RDMachine.ID) {
        if let existing = FileTransferManager.shared.transfers.first(where: { $0.machine.id == machine }) {
            route = .transfer(existing.id)
            return
        }
        FileTransferManager.shared.begin(for: machine)
    }

    @MainActor
    func showInMenuBar(machine: RDMachine.ID) {
        MenubarTool.shared.createRuncat(for: machine)
    }

    /// Batch Startup: pick servers, then open a terminal for each.
    @MainActor
    func batchStartup() {
        ServerPickerPanel.present(
            title: "Batch Startup",
            lead: "Open a terminal for each server you pick.",
            confirmTitle: "Open Terminals",
            allowsMany: true
        ) { machines in
            for machine in machines {
                TerminalManager.shared.createSession(withMachineID: machine) { _ in }
            }
            if let first = TerminalManager.shared.sessionContexts.last(where: { machines.contains($0.machine.id) }),
               self.opensAutomatically
            {
                self.route = .terminal(first.id)
            }
        }
    }

    func openSettings(_ category: String = SettingsCategory.general) {
        settingsSelection = category
        route = .settings
    }
}

enum SettingsCategory {
    static let general = "rayon-general"
    static let about = "rayon-about"
}
