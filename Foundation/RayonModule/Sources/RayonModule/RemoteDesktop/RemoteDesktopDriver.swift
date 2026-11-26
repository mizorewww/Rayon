//
//  RemoteDesktopDriver.swift
//  RayonModule
//
//  The protocol every remote-desktop backend (VNC, UU Remote, ...) speaks
//  to a session, plus the factory that picks a backend from a machine's
//  configuration. The session calls a driver on the main actor; drivers own
//  their own networking and threads, and everything they report goes back
//  through the session's nonisolated intake, which lands it on the main
//  actor.
//

import Foundation

/// A protocol backend driving one remote-desktop session. Its requirements
/// are main-actor isolated, not the protocol: a driver's own callbacks
/// (VNC's reader thread) stay nonisolated.
public protocol RemoteDesktopDriver: AnyObject, Sendable {
    /// Starts connecting. Called once; the driver may do all further work
    /// on its own threads.
    @MainActor func start(session: RemoteDesktopSession)
    /// Stops the session permanently. After `stop`, no more callbacks
    /// should reach the session.
    @MainActor func stop()

    /// Moves the pointer; button state rides along on the driver's own
    /// tracking (fed by `sendPointerButton`).
    @MainActor func sendPointerMove(normalizedX: Double, normalizedY: Double)
    /// A button went down or up at the given normalized position.
    @MainActor func sendPointerButton(_ button: MouseButton, isDown: Bool, normalizedX: Double, normalizedY: Double)
    /// Scroll deltas in wheel ticks (positive y = scroll up).
    @MainActor func sendScroll(deltaX: Double, deltaY: Double, normalizedX: Double, normalizedY: Double)
    /// A physical key went down or up. `keySym` is the driver's preferred
    /// symbolic name when known; `characters` carries the text a key
    /// produces so drivers can fall back to text input.
    @MainActor func sendKey(keyCode: UInt16, keySym: UInt32?, characters: String, isDown: Bool)
    /// Sends text as if typed (IME-friendly path when the driver has one).
    @MainActor func sendText(_ text: String)
    /// Pushes the local pasteboard to the remote clipboard.
    @MainActor func sendClipboard(_ text: String)

    /// Switches the display being viewed (multi-monitor hosts).
    @MainActor func selectDisplay(_ displayID: Int)
    /// Applies a frame rate, quality and colour (UU Remote; VNC has none).
    @MainActor func updateStream(_ settings: RemoteDesktopStreamSettings)
    /// Asks the host for a full refresh / keyframe.
    @MainActor func requestKeyframeOrRefresh()
    /// Adds a display of the given pixel size on the host, where it can
    /// make one (a UU virtual screen), and switches to it.
    @MainActor func addVirtualDisplay(width: Int, height: Int)
    /// Removes a display `addVirtualDisplay` (or another viewer) made.
    @MainActor func removeVirtualDisplay(_ displayID: Int)
}

public extension RemoteDesktopDriver {
    func addVirtualDisplay(width _: Int, height _: Int) {}
    func removeVirtualDisplay(_: Int) {}
}

/// Picks the backend for a machine. `.vnc` and `.uuRemote` are built in.
public enum RemoteDesktopDriverFactory {
    /// Creates a driver for the session's protocol (the machine's, unless
    /// the session was opened with another); nil for `.none`.
    @MainActor
    static func make(for machine: RDMachine, session: RemoteDesktopSession) -> RemoteDesktopDriver? {
        switch session.protocolType {
        case .none:
            return nil
        case .vnc:
            return VNCRFBDriver(machine: machine, session: session)
        case .uuRemote:
            return UURemoteDesktopDriver(session: session)
        }
    }
}
