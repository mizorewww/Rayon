//
//  PortForwardPresentation.swift
//  RayonModule
//
//  What a port-forward row shows for a session state: a dot and a word.
//  Shared by the macOS and iOS tables so the two cannot drift apart.
//

import RayonDesign

public struct PortForwardPresentation: Equatable {
    public let status: RXStatus
    public let text: String

    /// `running` is whether the backend still holds the session. A
    /// finished session's last state keeps showing in the row, and a
    /// fresh row has no state yet, so both inputs matter.
    public init(state: PortForwardContext.Lifecycle?, running: Bool) {
        switch state {
        case .awaitingConnect, .openingChannel:
            (status, text) = (.running, String(localized: "Connecting", bundle: .module))
        case .forwardRunning:
            (status, text) = running ? (.success, String(localized: "Running", bundle: .module)) : (.off, String(localized: "Stopped", bundle: .module))
        case .failedConnect:
            (status, text) = (.danger, String(localized: "Could not connect", bundle: .module))
        case .failedAuthenticate:
            (status, text) = (.danger, String(localized: "Could not sign in", bundle: .module))
        case .portInUse:
            (status, text) = (.danger, String(localized: "Port in use", bundle: .module))
        case .forwardStopped:
            (status, text) = running ? (.danger, String(localized: "Forward ended", bundle: .module)) : (.off, String(localized: "Stopped", bundle: .module))
        case .terminating, .terminated, .none:
            (status, text) = running ? (.running, String(localized: "Starting", bundle: .module)) : (.off, String(localized: "Stopped", bundle: .module))
        }
    }
}
