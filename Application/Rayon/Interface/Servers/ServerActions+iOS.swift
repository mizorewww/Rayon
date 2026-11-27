//
//  ServerActions+iOS.swift
//  Rayon
//
//  Opening a server's editor and its tools on iPhone and iPad: a tool
//  shows on the server's page.
//

#if os(iOS)
    import MachineStatusView
    import RayonModule
    import SwiftUI

    extension ServerActions {
        static func edit(_ machine: RDMachine.ID) {
            RayonUtil.presentModalSheet(rootView: ServerEditor(machine: machine))
        }

        static func create() {
            RayonUtil.presentModalSheet(rootView: ServerEditor())
        }

        /// The server's terminal on its page: the one open, else a new one.
        static func openTerminal(_ machine: RDMachine.ID) {
            if SessionDirectory.hasSession(machine, .terminal) {
                SessionNavigation.shared.reveal(.server(machine), tool: .terminal)
            } else {
                TerminalManager.shared.begin(for: machine)
            }
        }

        static func openMonitor(_ machine: RDMachine.ID) {
            do {
                let existing = MonitorCenter.shared.session(for: machine)
                let session = try MonitorCenter.shared.begin(for: machine)
                // An existing monitor is brought forward even when sessions do
                // not open automatically; a new one waits for the setting.
                guard existing != nil || AppSettings.showsSessionOnConnect.value else { return }
                SessionNavigation.shared.reveal(.server(session.machine.id), tool: .monitor)
            } catch {
                Indicator.error(String(localized: "Cannot open monitor"))
            }
        }

        /// The server's remote desktop, on the server's page.
        static func openDesktop(_ machine: RDMachine.ID) {
            let existing = RemoteDesktopManager.shared.session(for: machine)
            guard let session = RemoteDesktopManager.shared.begin(for: machine) else { return }
            guard existing != nil || AppSettings.showsSessionOnConnect.value else { return }
            SessionNavigation.shared.reveal(.server(session.machine.id), tool: .desktop)
        }

        /// Pick servers, then open a terminal for each.
        static func batchStartup() {
            ServerPicker.present(title: "Batch Startup", confirmTitle: "Open") { machines in
                for machine in machines {
                    TerminalManager.shared.begin(for: machine, force: true)
                }
            }
        }
    }

    extension ServerTool {
        /// Shows this tool for the server, reusing a session that is already open.
        @MainActor
        func show(_ machine: RDMachine.ID) {
            switch self {
            case .terminal: ServerActions.openTerminal(machine)
            case .monitor: ServerActions.openMonitor(machine)
            case .desktop: ServerActions.openDesktop(machine)
            case .files, .editor: open(machine)
            }
        }
    }

#endif
