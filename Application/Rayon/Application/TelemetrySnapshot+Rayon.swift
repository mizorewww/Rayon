//
//  TelemetrySnapshot+Rayon.swift
//  Rayon
//
//  The app's state for the daily report, as counts and flags only.
//

import RayonModule
import RayonTerminal

@MainActor
extension TelemetrySnapshot {
    static var rayon: TelemetrySnapshot {
        let store = RayonStore.shared
        let themed = TerminalSettings.shared.applied["theme"] != nil
        let redaction: TelemetryReport.RedactionMode = switch AppSettings.serverRedaction.value {
        case .none: .none
        case .sensitive: .address
        case .all: .all
        }
        return TelemetrySnapshot(
            savedHosts: store.machines.count,
            identities: store.identities.count,
            keyTypes: Set(store.identities.compactMap(\.telemetryKeyType)),
            iCloudSyncEnabled: CloudSyncModel.shared.preferences.isOn,
            customTheme: themed,
            redactionMode: redaction
        )
    }
}
