//
//  UURemoteDesktopDriver.swift
//  RayonModule
//
//  A UU Remote desktop as a RemoteDesktopDriver: a UURemoteKit connection
//  whose events go to the session, and whose frames become the canvas's
//  images.
//

import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

final class UURemoteDesktopDriver: RemoteDesktopDriver, @unchecked Sendable {
    private let session: RemoteDesktopSession
    /// Main actor only.
    private var connection: UURemoteConnection?

    init(session: RemoteDesktopSession) {
        self.session = session
    }

    /// Callers are on the main actor; the protocol does not say so.
    private func onMain(_ work: @escaping @MainActor (UURemoteConnection) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { if let connection { work(connection) } }
        } else {
            Task { @MainActor in if let connection = self.connection { work(connection) } }
        }
    }

    func start(session: RemoteDesktopSession) {
        MainActor.assumeIsolated {
            let machine = session.machine
            let connection = UURemoteConnections.shared.desktop(
                for: machine.uuTarget,
                settings: UUStreamSettings(session.streamSettings),
                localRefreshRate: RemoteDesktopSession.localRefreshRate(),
                preferredScreenID: machine.uuDisplayID == 0 ? nil : machine.uuDisplayID
            )
            let session = self.session
            connection.onFrame = { frame in
                var image: CGImage?
                VTCreateCGImageFromCVPixelBuffer(frame.pixelBuffer, options: nil, imageOut: &image)
                session.reportFrame(image, size: CGSize(width: frame.width, height: frame.height))
            }
            connection.onEvent = { event in Self.report(event, to: session) }
            self.connection = connection
            connection.start()
        }
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
        onMain { $0.stop() }
    }

    func sendPointerMove(normalizedX: Double, normalizedY: Double) {
        onMain { $0.movePointer(x: normalizedX, y: normalizedY) }
    }

    func sendPointerButton(_ button: MouseButton, isDown: Bool, normalizedX: Double, normalizedY: Double) {
        let uuButton: UUMouseButton = switch button {
        case .left: .left
        case .middle: .middle
        case .right: .right
        case .back: .back
        case .forward: .forward
        }
        onMain { $0.pressButton(uuButton, isDown: isDown, x: normalizedX, y: normalizedY) }
    }

    func sendScroll(deltaX: Double, deltaY: Double, normalizedX: Double, normalizedY: Double) {
        onMain { $0.scroll(dx: deltaX, dy: deltaY, x: normalizedX, y: normalizedY) }
    }

    /// `keyCode` is a Carbon virtual keycode, what a Mac host takes; a
    /// Windows host gets the matching virtual-key code.
    func sendKey(keyCode: UInt16, keySym _: UInt32?, characters _: String, isDown: Bool) {
        onMain { connection in
            let code = connection.hostIsWindows ? (RemoteDesktopKeymap.windowsVKForCarbon[keyCode] ?? Int32(keyCode)) : Int32(keyCode)
            connection.key(code, isDown: isDown)
        }
    }

    func sendText(_ text: String) {
        onMain { $0.typeText(text) }
    }

    func sendClipboard(_ text: String) {
        onMain { $0.setRemoteClipboard(text) }
    }

    func selectDisplay(_ displayID: Int) {
        onMain { $0.selectScreen(displayID) }
    }

    func updateStream(_ settings: RemoteDesktopStreamSettings) {
        onMain { $0.updateStream(UUStreamSettings(settings)) }
    }

    func requestKeyframeOrRefresh() {
        onMain { $0.requestKeyFrame() }
    }

    func addVirtualDisplay(width: Int, height: Int) {
        onMain { $0.addVirtualScreen(width: width, height: height) }
    }

    func removeVirtualDisplay(_ displayID: Int) {
        onMain { $0.removeVirtualScreen(displayID) }
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
