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
            (status, text) = (.running, "Connecting")
        case .forwardRunning:
            (status, text) = running ? (.success, "Running") : (.off, "Stopped")
        case .failedConnect:
            (status, text) = (.danger, "Could not connect")
        case .failedAuthenticate:
            (status, text) = (.danger, "Could not sign in")
        case .forwardStopped:
            (status, text) = running ? (.danger, "Forward ended") : (.off, "Stopped")
        case .terminating, .terminated, .none:
            (status, text) = running ? (.running, "Starting") : (.off, "Stopped")
        }
    }
}
