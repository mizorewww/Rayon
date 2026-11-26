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

final class VNCRFBDriver: RemoteDesktopDriver, @unchecked Sendable {
    private let machine: RDMachine
    private weak var session: RemoteDesktopSession?
    private var client: VNCRFBClient?
    private var tunnel: VNCSSHTunnel?
    private var worker: Task<Void, Never>?
    private let stateLock = NSLock()
    private var stopped = false
    /// Cursor + framebuffer state, touched by both the input calls (main
    /// actor) and the client delegate (reader thread).
    private let cursorLock = NSLock()
    /// The last cursor shape reported; its x,y hold the hotspot in pixels.
    private var cursorShape: RemoteCursorInfo?
    /// The pointer's last normalized position; the remote cursor follows
    /// it (the host does not report cursor moves itself).
    private var pointerX = 0.0
    private var pointerY = 0.0
    /// The remote framebuffer's pixel size, learned from frame updates.
    private var framebufferSize: CGSize = .zero

    init(machine: RDMachine, session: RemoteDesktopSession) {
        self.machine = machine
        self.session = session
    }

    // MARK: - RemoteDesktopDriver

    func start(session: RemoteDesktopSession) {
        let worker = Task { await bootstrap() }
        stateLock.withLock {
            stopped = false
            self.worker = worker
        }
    }

    func stop() {
        let (worker, tunnel, client) = stateLock.withLock {
            stopped = true
            return (self.worker, self.tunnel, self.client)
        }
        worker?.cancel()
        tunnel?.stop()
        client?.stop()
    }

    private var currentClient: VNCRFBClient? {
        stateLock.withLock { client }
    }

    private func isStopped() -> Bool {
        stateLock.withLock { stopped }
    }

    private func bootstrap() async {
        var transport: VNCTransport?
        if machine.vncOverSSH {
            reportPhase(.connecting("Opening the SSH tunnel"), hint: "Opening SSH tunnel…")
            let tunnel = VNCSSHTunnel(
                machine: machine,
                targetPort: UInt16(machine.vncPort) ?? 5900
            )
            let proceed = stateLock.withLock { () -> Bool in
                guard !stopped else { return false }
                self.tunnel = tunnel
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
        let proceed = stateLock.withLock { () -> Bool in
            guard !stopped else { return false }
            self.client = client
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
        let cursor = cursorLock.withLock { () -> RemoteCursorInfo? in
            pointerX = normalizedX
            pointerY = normalizedY
            return cursorAtCurrentPointer()
        }
        if let cursor { session?.reportCursor(cursor) }
    }

    /// The cursor at the tracked pointer position, or nil if there is no
    /// shape or framebuffer yet. Call while `cursorLock` is held.
    private func cursorAtCurrentPointer() -> RemoteCursorInfo? {
        guard let shape = cursorShape,
              framebufferSize.width > 0, framebufferSize.height > 0 else { return nil }
        var cursor = shape
        // shape.x/shape.y are the hotspot in cursor-image pixels, so the
        // image's top-left lands at pointer − hotspot (all normalized).
        cursor.x = pointerX - shape.x / framebufferSize.width
        cursor.y = pointerY - shape.y / framebufferSize.height
        return cursor
    }
}

// MARK: - VNCRFBClientDelegate

extension VNCRFBDriver: VNCRFBClientDelegate {
    func client(_: VNCRFBClient, didChangePhase phase: RemoteDesktopPhase, hint: String?) {
        reportPhase(phase, hint: hint)
    }

    func client(_: VNCRFBClient, didUpdateFrame image: CGImage?, size: CGSize, desktopName: String?) {
        cursorLock.withLock { framebufferSize = size }
        session?.reportFrame(image.map(RemoteDesktopPicture.image), size: size, desktopName: desktopName)
    }

    func client(_: VNCRFBClient, didUpdateCursor cursor: RemoteCursorInfo?) {
        let positioned = cursorLock.withLock { () -> RemoteCursorInfo? in
            cursorShape = cursor
            return cursorAtCurrentPointer()
        }
        if let positioned { session?.reportCursor(positioned) }
    }

    func client(_: VNCRFBClient, didReceiveClipboard text: String) {
        session?.reportRemoteClipboard(text)
    }
}
