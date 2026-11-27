//
//  TerminalContext+Terminfo.swift
//  RayonModule
//
//  Which terminal type an SSH session asks for: xterm-ghostty where the
//  server has (or now gets) Ghostty's terminfo, xterm-256color elsewhere.
//  Runs after sign-in and before the shell.
//

import Foundation
import RayonSSH

extension TerminalContext {
    func prepareTerminalType(on connection: SSHConnection) async -> String {
        guard AppSettings.installsTerminfo.value else { return GhosttyTerminfo.fallbackType }
        // A saved server that has it: no command at all.
        if remoteType == .machine, RayonStore.workerMachine(for: machine.id).map(GhosttyTerminfo.isCached(on:)) == true {
            return GhosttyTerminfo.terminalType
        }
        // The command prints what it found; a failure or timeout reads as none.
        let result = try? await connection.execute(GhosttyTerminfo.installCommand, timeout: .seconds(10))
        let output = result.map { String(decoding: $0.output + $0.errorOutput, as: UTF8.self) } ?? ""
        switch GhosttyTerminfo.outcome(of: output) {
        case .present:
            rememberTerminfo()
            return GhosttyTerminfo.terminalType
        case .installed:
            putInformation("[i] \(String(localized: "Installed Ghostty's terminfo on this server (~/.terminfo), so programs there know this terminal.", bundle: .module))")
            rememberTerminfo()
            return GhosttyTerminfo.terminalType
        case .failed:
            putInformation("[i] This server could not take Ghostty's terminfo (no tic, or ~/.terminfo not writable); running as \(GhosttyTerminfo.fallbackType).")
            return GhosttyTerminfo.fallbackType
        }
    }

    /// Saved servers remember it, so later terminals skip the check.
    private func rememberTerminfo() {
        guard remoteType == .machine else { return }
        let id = machine.id
        Task { @MainActor in
            RayonStore.shared.updateMachine(id) { saved in
                guard !saved.hasGhosttyTerminfo else { return }
                saved.ghosttyTerminfoVersion = GhosttyTerminfo.version
            }
        }
    }
}
