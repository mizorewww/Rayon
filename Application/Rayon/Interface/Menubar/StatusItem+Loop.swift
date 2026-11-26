//
//  StatusItem+Loop.swift
//  Rayon (macOS)
//

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

        RayonStore.shared.$machineGroup
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] group in
                MainActor.assumeIsolated {
                    guard let self, !group[self.machine.id].isNotPlaceholder() else { return }
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
