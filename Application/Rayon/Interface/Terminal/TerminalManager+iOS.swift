//
//  TerminalManager+iOS.swift
//  Rayon
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    extension TerminalManager {
        func begin(for machineId: RDMachine.ID, force: Bool = false) {
            if !force {
                for terminal in terminals where terminal.machine.id == machineId {
                    Indicator.confirm(
                        message: "Another terminal for this machine is already running",
                        skippable: true
                    ) { confirmed in
                        guard confirmed else { return }
                        MainActor.assumeIsolated {
                            self.begin(for: machineId, force: true)
                        }
                    }
                    return
                }
            }
            guard let machine = RayonStore.shared.machine(machineId) else {
                Indicator.error(String(localized: "Unknown Bad Data"))
                return
            }
            createSession(withMachineObject: machine, askingToResume: true)
        }

        func begin(for command: SSHCommandReader, force: Bool = false) {
            if !force {
                for terminal in terminals where terminal.command == command {
                    Indicator.confirm(
                        message: "Another terminal for this command is already running",
                        skippable: true
                    ) { confirmed in
                        guard confirmed else { return }
                        MainActor.assumeIsolated {
                            self.begin(for: command, force: true)
                        }
                    }
                    return
                }
            }
            createSession(withCommand: command)
        }

        /// A terminal to `machine`. A UU Remote device may have sessions to
        /// resume: they are offered first, as on the Mac.
        func createSession(
            withMachineObject machine: RDMachine,
            askingToResume: Bool,
            completion: @escaping (Context) -> Void = { _ in }
        ) {
            guard askingToResume, machine.isUURemoteDevice else {
                createSession(withMachineObject: machine, resuming: nil, completion: completion)
                return
            }
            UURemoteSessionPickerView.present(machine: machine) { choice in
                switch choice {
                case .new:
                    self.createSession(withMachineObject: machine, resuming: nil, completion: completion)
                case let .resume(id):
                    self.createSession(withMachineObject: machine, resuming: id, completion: completion)
                case nil:
                    break
                }
            }
        }

        /// One more tab like `context`: the same server (asking to resume on a
        /// UU Remote device) or the same Quick Connect command.
        func openAnotherTab(like context: Context, completion: @escaping (Context) -> Void = { _ in }) {
            switch context.remoteType {
            case .machine:
                guard let machine = RayonStore.shared.machine(context.machine.id) else {
                    Indicator.error(String(localized: "This server's details could not be read."))
                    return
                }
                createSession(withMachineObject: machine, askingToResume: true, completion: completion)
            case .command:
                if let command = context.command {
                    completion(createSession(withCommand: command))
                }
            case .local:
                // No local shell on iOS.
                break
            }
        }
    }

    extension TerminalSessionActions {
        @MainActor
        static func close(_ context: TerminalManager.Context, then: @escaping @MainActor () -> Void = {}) {
            confirmClose(context) {
                TerminalManager.shared.closeSession(withContextID: context.id)
                then()
            }
        }
    }

#endif
