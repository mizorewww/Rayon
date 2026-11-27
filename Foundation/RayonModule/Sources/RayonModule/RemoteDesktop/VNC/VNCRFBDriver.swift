//
//  VNCRFBDriver.swift
//  RayonModule
//
//  The RemoteDesktopDriver for VNC: owns the optional SSH tunnel and the
//  RFB client, wires the client's reports into the session, and turns the
//  session's input calls into RFB messages.
//

import CoreGraphics
import Foundation
import Synchronization

final class VNCRFBDriver: RemoteDesktopDriver {
    private let machine: RDMachine
    private weak let session: RemoteDesktopSession?

    /// What `stop` must reach, set as the bootstrap makes it.
    private struct Parts {
        var client: VNCRFBClient?
        var tunnel: VNCSSHTunnel?
        var worker: Task<Void, Never>?
        var stopped = false
    }

    private let parts = Mutex(Parts())

    /// Cursor + framebuffer state, touched by both the input calls (main
    /// actor) and the client delegate (the session task).
    private struct Pointer {
        /// The last cursor shape reported; its x,y hold the hotspot in pixels.
        var shape: RemoteCursorInfo?
        /// The pointer's last normalized position; the remote cursor follows
        /// it (the host does not report cursor moves itself).
        var x = 0.0
        var y = 0.0
        /// The remote framebuffer's pixel size, learned from frame updates.
        var framebufferSize: CGSize = .zero

        /// The cursor at the pointer, or nil if there is no shape or
        /// framebuffer yet.
        var cursor: RemoteCursorInfo? {
            guard let shape, framebufferSize.width > 0, framebufferSize.height > 0 else { return nil }
            var cursor = shape
            // shape.x/shape.y are the hotspot in cursor-image pixels, so the
            // image's top-left lands at pointer − hotspot (all normalized).
            cursor.x = x - shape.x / framebufferSize.width
            cursor.y = y - shape.y / framebufferSize.height
            return cursor
        }
    }

    private let pointer = Mutex(Pointer())

    init(machine: RDMachine, session: RemoteDesktopSession) {
        self.machine = machine
        self.session = session
    }

    // MARK: - RemoteDesktopDriver

    func start(session: RemoteDesktopSession) {
        let worker = Task { await bootstrap() }
        parts.withLock {
            $0.stopped = false
            $0.worker = worker
        }
    }

    func stop() {
        let (worker, tunnel, client) = parts.withLock {
            $0.stopped = true
            return ($0.worker, $0.tunnel, $0.client)
        }
        worker?.cancel()
        tunnel?.stop()
        client?.stop()
    }

    private var currentClient: VNCRFBClient? {
        parts.withLock { $0.client }
    }

    private func bootstrap() async {
        var transport: VNCTransport?
        if machine.vncOverSSH {
            reportPhase(.connecting("Opening the SSH tunnel"), hint: "Opening SSH tunnel…")
            let tunnel = VNCSSHTunnel(
                machine: machine,
                targetPort: UInt16(machine.vncPort) ?? 5900
            )
            let proceed = parts.withLock { parts -> Bool in
                guard !parts.stopped else { return false }
                parts.tunnel = tunnel
                return true
            }
            guard proceed else { return }
            do {
                transport = try await tunnel.open()
            } catch let error as RemoteDesktopFailure {
                reportPhase(.failed(error.message))
                return
            } catch {
                return // stopped while opening
            }
        }

        let identity = RayonStore.workerAssociatedIdentity(for: machine)
        let client = VNCRFBClient(
            configuration: .init(
                host: machine.remoteAddress,
                port: UInt16(machine.vncPort) ?? 5900,
                password: machine.resolvedVNCPassword(identity: identity),
                username: machine.resolvedVNCUsername(identity: identity),
                shared: machine.vncShared,
                timeout: max(TimeInterval(RayonStore.workerTimeoutNumber.intValue), 10),
                transport: transport
            ),
            delegate: self
        )
        let proceed = parts.withLock { parts -> Bool in
            guard !parts.stopped else { return false }
            parts.client = client
            return true
        }
        guard proceed else {
            transport?.close()
            return
        }
        client.start()
    }

    private func reportPhase(_ phase: RemoteDesktopPhase, hint: String? = nil) {
        session?.reportPhase(phase, hint: hint)
    }

    // MARK: - Input

    func sendPointerMove(normalizedX: Double, normalizedY: Double) {
        currentClient?.pointerMoved(normalizedX: normalizedX, normalizedY: normalizedY)
        updateCursorPosition(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    func sendPointerButton(_ button: MouseButton, isDown: Bool, normalizedX: Double, normalizedY: Double) {
        updateCursorPosition(normalizedX: normalizedX, normalizedY: normalizedY)
        currentClient?.pointerButton(button, isDown: isDown, normalizedX: normalizedX, normalizedY: normalizedY)
    }

    func sendScroll(deltaX: Double, deltaY: Double, normalizedX: Double, normalizedY: Double) {
        updateCursorPosition(normalizedX: normalizedX, normalizedY: normalizedY)
        currentClient?.scrolled(deltaX: deltaX, deltaY: deltaY, normalizedX: normalizedX, normalizedY: normalizedY)
    }

    func sendKey(keyCode: UInt16, keySym: UInt32?, characters: String, isDown: Bool) {
        currentClient?.keyEvent(keyCode: keyCode, keySym: keySym, characters: characters, isDown: isDown)
    }

    func sendText(_ text: String) {
        currentClient?.typeText(text)
    }

    func sendClipboard(_ text: String) {
        currentClient?.setClipboard(text)
    }

    func selectDisplay(_: Int) {
        // Standard RFB has no display switching; pseudo-encodings such as
        // ExtendedDesktopSize cover resizing, not monitor selection.
    }

    func updateStream(_: RemoteDesktopStreamSettings) {
        // The RFB wire has no quality knob; encodings are negotiated once.
    }

    func requestKeyframeOrRefresh() {
        // A non-incremental update request asks for the whole framebuffer.
        currentClient?.requestUpdate(incremental: false)
    }

    /// Records the pointer position and re-emits the cursor overlay at
    /// pointer − hotspot, all in normalized framebuffer coordinates.
    private func updateCursorPosition(normalizedX: Double, normalizedY: Double) {
        let cursor = pointer.withLock { pointer in
            pointer.x = normalizedX
            pointer.y = normalizedY
            return pointer.cursor
        }
        if let cursor { session?.reportCursor(cursor) }
    }
}

// MARK: - VNCRFBClientDelegate

extension VNCRFBDriver: VNCRFBClientDelegate {
    func client(_: VNCRFBClient, didChangePhase phase: RemoteDesktopPhase, hint: String?) {
        reportPhase(phase, hint: hint)
    }

    func client(_: VNCRFBClient, didUpdateFrame picture: RemoteDesktopPicture?, size: CGSize, desktopName: String?) {
        pointer.withLock { $0.framebufferSize = size }
        session?.reportFrame(picture, size: size, desktopName: desktopName)
    }

    func client(_: VNCRFBClient, didUpdateCursor cursor: RemoteCursorInfo?) {
        let positioned = pointer.withLock { pointer in
            pointer.shape = cursor
            return pointer.cursor
        }
        if let positioned { session?.reportCursor(positioned) }
    }

    func client(_: VNCRFBClient, didReceiveClipboard text: String) {
        session?.reportRemoteClipboard(text)
    }
}
