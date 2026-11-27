//
//  UURemoteDesktopDriver.swift
//  RayonModule
//
//  A UU Remote desktop as a RemoteDesktopDriver: a UURemoteKit connection
//  whose events go to the session, and whose decoded frames go to the
//  canvas as they are.
//

import CoreGraphics
import CoreVideo
import Foundation

@MainActor
final class UURemoteDesktopDriver: RemoteDesktopDriver {
    private let session: RemoteDesktopSession
    private var connection: UURemoteConnection?

    init(session: RemoteDesktopSession) {
        self.session = session
    }

    func start(session: RemoteDesktopSession) {
        let machine = session.machine
        let connection = UURemoteConnections.shared.desktop(
            for: machine.uuTarget,
            settings: UUStreamSettings(session.streamSettings),
            localRefreshRate: RemoteDesktopSession.localRefreshRate(),
            preferredScreenID: machine.uuDisplayID == 0 ? nil : machine.uuDisplayID
        )
        let session = self.session
        connection.onFrame = { frame in
            let size = CGSize(width: frame.width, height: frame.height)
            // VideoToolbox decodes onto IOSurfaces; no decoder here makes
            // a buffer that is not on one.
            guard let surface = CVPixelBufferGetIOSurface(frame.pixelBuffer)?.takeUnretainedValue() else { return }
            session.reportFrame(RemoteDesktopPicture(surface: surface), size: size)
        }
        connection.onEvent = { event in Self.report(event, to: session) }
        self.connection = connection
        connection.start()
    }

    private static func report(_ event: UURemoteEvent, to session: RemoteDesktopSession) {
        switch event {
        case let .phase(phase):
            switch phase {
            case let .connecting(step): session.reportPhase(.connecting(step))
            case .connected: session.reportPhase(.connected)
            case .locked: session.reportPhase(.authenticating)
            case let .failed(reason): session.reportPhase(.failed(reason))
            case .closed: session.reportPhase(.closed(nil))
            }
        case let .hint(text): session.reportHint(text)
        case let .screens(screens, selected):
            session.reportDisplays(screens.map(RemoteDisplayInfo.init), selected: selected ?? -1)
        case let .cursor(cursor):
            session.reportCursor(RemoteCursorInfo(x: cursor.x, y: cursor.y, width: cursor.width, height: cursor.height, image: cursor.image, visible: cursor.visible))
        case let .roundTrip(milliseconds): session.reportRTT(milliseconds)
        case let .network(stats):
            session.reportNetwork(RemoteDesktopNetwork(bitsPerSecond: stats.bitsPerSecond, lossPercent: stats.lossPercent, relayed: stats.relayed))
        case let .remoteClipboard(text): session.reportRemoteClipboard(text)
        case let .notice(text): session.reportNotice(text)
        case let .streamChanged(settings, notice): session.reportStreamChanged(RemoteDesktopStreamSettings(settings), notice: notice)
        case let .streamRefused(settings, reason): session.reportStreamRefused(RemoteDesktopStreamSettings(settings), reason: reason)
        }
    }

    func stop() {
        connection?.stop()
    }

    func sendPointerMove(normalizedX: Double, normalizedY: Double) {
        connection?.movePointer(x: normalizedX, y: normalizedY)
    }

    func sendPointerButton(_ button: MouseButton, isDown: Bool, normalizedX: Double, normalizedY: Double) {
        let uuButton: UUMouseButton = switch button {
        case .left: .left
        case .middle: .middle
        case .right: .right
        case .back: .back
        case .forward: .forward
        }
        connection?.pressButton(uuButton, isDown: isDown, x: normalizedX, y: normalizedY)
    }

    func sendScroll(deltaX: Double, deltaY: Double, normalizedX: Double, normalizedY: Double) {
        connection?.scroll(dx: deltaX, dy: deltaY, x: normalizedX, y: normalizedY)
    }

    /// `keyCode` is a Carbon virtual keycode, what a Mac host takes; a
    /// Windows host gets the matching virtual-key code.
    func sendKey(keyCode: UInt16, keySym _: UInt32?, characters _: String, isDown: Bool) {
        guard let connection else { return }
        let code = connection.hostIsWindows ? (RemoteDesktopKeymap.windowsVKForCarbon[keyCode] ?? Int32(keyCode)) : Int32(keyCode)
        connection.key(code, isDown: isDown)
    }

    func sendText(_ text: String) {
        connection?.typeText(text)
    }

    func sendClipboard(_ text: String) {
        connection?.setRemoteClipboard(text)
    }

    func selectDisplay(_ displayID: Int) {
        connection?.selectScreen(displayID)
    }

    func updateStream(_ settings: RemoteDesktopStreamSettings) {
        connection?.updateStream(UUStreamSettings(settings))
    }

    func requestKeyframeOrRefresh() {
        connection?.requestKeyFrame()
    }

    func addVirtualDisplay(width: Int, height: Int) {
        connection?.addVirtualScreen(width: width, height: height)
    }

    func removeVirtualDisplay(_ displayID: Int) {
        connection?.removeVirtualScreen(displayID)
    }
}

extension UUStreamSettings {
    init(_ settings: RemoteDesktopStreamSettings) {
        self.init(fps: settings.fps, quality: settings.quality, trueColor: settings.trueColor)
    }
}

extension RemoteDesktopStreamSettings {
    init(_ settings: UUStreamSettings) {
        self.init(fps: settings.fps, quality: settings.quality, trueColor: settings.trueColor)
    }
}

extension RemoteDisplayInfo {
    init(_ screen: UUScreen) {
        self.init(id: screen.id, name: screen.name, width: screen.width, height: screen.height, fps: screen.fps, isPrimary: screen.isPrimary, isVirtual: screen.isVirtual, videoTrackIndex: screen.videoTrackIndex)
    }
}
