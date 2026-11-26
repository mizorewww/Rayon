//
//  TerminalContext+Terminfo.swift
//  RayonModule
//
//  Which terminal type an SSH session asks for: xterm-ghostty where the
//  server has (or now gets) Ghostty's terminfo, xterm-256color elsewhere.
//  Runs on the session's worker queue, after sign-in and before the shell.
//

import Foundation

extension TerminalContext {
    func prepareTerminalType() -> String {
        guard GhosttyTerminfo.installsAutomatically else { return GhosttyTerminfo.fallbackType }
        // A saved server that has it: no command at all.
        if remoteType == .machine, RayonStore.workerMachine(for: machine.id).map(GhosttyTerminfo.isCached(on:)) == true {
            return GhosttyTerminfo.terminalType
        }
        var output = ""
        let outputLock = NSLock()
        shell.beginExecute(withCommand: GhosttyTerminfo.installCommand, withTimeout: 10) {
        } withOutput: { chunk in
            outputLock.withLock { output += chunk }
        } withContinuationHandler: { [weak self] in
            self?.continueDecision ?? false
        }
        switch GhosttyTerminfo.outcome(of: outputLock.withLock { output }) {
        case .present:
            rememberTerminfo()
            return GhosttyTerminfo.terminalType
        case .installed:
            putInformation("[i] Installed Ghostty's terminfo on this server (~/.terminfo), so programs there know this terminal.")
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
            guard var saved = RayonStore.shared.machine(id), !saved.hasGhosttyTerminfo else { return }
            saved.ghosttyTerminfoVersion = GhosttyTerminfo.version
            RayonStore.shared.save(saved)
        }
    }
}
