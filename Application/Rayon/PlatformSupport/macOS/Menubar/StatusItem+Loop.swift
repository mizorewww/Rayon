//
//  StatusItem+Loop.swift
//  Rayon
//

#if os(macOS)
import Combine
import MachineStatus
import MachineStatusView
import RayonModule
import SwiftUI

extension MenubarStatusItem {
    @MainActor func observeSession() {
        // One update per published round or phase change; no polling.
        session.$snapshot
            .combineLatest(session.$phase)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, phase in
                MainActor.assumeIsolated { self?.refresh(status: snapshot.status, phase: phase) }
            }
            .store(in: &cancellables)

        RayonStore.shared.$machines
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] machines in
                MainActor.assumeIsolated {
                    guard let self, !machines.contains(where: { $0.id == self.machine.id }) else { return }
                    self.closeThisItem()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor func refresh(status: ServerStatus, phase: MonitorSession.Phase) {
        let reachable = phase == .connected && status.hasData
        var title = ""
        if reachable {
            let up = RXFormat.rateString(Double(status.totalTransmitPerSecond))
            let down = RXFormat.rateString(Double(status.totalReceivePerSecond))
            title = "↑ \(up)\n↓ \(down)"
        }
        updateDisplay(title: title, cpu: reachable ? Double(status.processor.summary.sumUsed) : nil)
    }
}

#endif
