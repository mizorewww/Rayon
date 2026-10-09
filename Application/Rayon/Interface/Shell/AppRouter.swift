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

    @Published var route: Route = .home {
        didSet { if !route.isSession { lastPlace = route } }
    }
    /// The last page that is not a session; closing a session returns here.
    private(set) var lastPlace: Route = .home
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
                if !contexts.contains(where: { $0.id == id }) { self.route = self.lastPlace }
            }
            .store(in: &cancellables)
        MonitorCenter.shared.$sessions
            .sink { [weak self] sessions in
                guard let self, case let .monitor(id) = self.route else { return }
                if !sessions.contains(where: { $0.id == id }) { self.route = self.lastPlace }
            }
            .store(in: &cancellables)
        FileTransferManager.shared.$transfers
            .sink { [weak self] transfers in
                guard let self, case let .transfer(id) = self.route else { return }
                if !transfers.contains(where: { $0.id == id }) { self.route = self.lastPlace }
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
        let manager = FileTransferManager.shared
        if let existing = manager.transfers.first(where: { $0.machine.id == machine }) {
            route = .transfer(existing.id)
            return
        }
        manager.begin(for: machine)
        // Like Monitor, Files opens its page right away and connects in place.
        if let started = manager.transfers.last(where: { $0.machine.id == machine }) {
            route = .transfer(started.id)
        }
    }

    @MainActor
    func showInMenuBar(machine: RDMachine.ID) {
        MenubarTool.shared.createRuncat(for: machine)
    }

    /// Pick one or more servers, then open a terminal for each.
    @MainActor
    func openTerminals() {
        ServerPickerPanel.present(
            title: "Open Terminals",
            confirmTitle: "Open",
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

extension Route {
    var isSession: Bool {
        switch self {
        case .terminal, .monitor, .transfer: return true
        default: return false
        }
    }
}

enum SettingsCategory {
    static let general = "rayon-general"
    static let about = "rayon-about"
}
