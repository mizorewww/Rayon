//
//  VNCRFBClient.swift
//  RayonModule
//
//  The RFB session state machine: banner → security → init → encodings →
//  the read loop that turns rectangles into framebuffer updates and
//  clipboard/cursor events. The session runs in one task; input calls from
//  the main actor only queue messages on the transport, never wait on it.
//

import CoreGraphics
import Foundation
import os

/// The events a session reports back, delivered from the client's session
/// task — the driver forwards them into the main-actor session.
protocol VNCRFBClientDelegate: AnyObject, Sendable {
    func client(_ client: VNCRFBClient, didChangePhase phase: RemoteDesktopPhase, hint: String?)
    func client(_ client: VNCRFBClient, didUpdateFrame image: CGImage?, size: CGSize, desktopName: String?)
    func client(_ client: VNCRFBClient, didUpdateCursor cursor: RemoteCursorInfo?)
    func client(_ client: VNCRFBClient, didReceiveClipboard text: String)
}

final class VNCRFBClient: Sendable {
    struct Configuration: Sendable {
        var host: String
        var port: UInt16
        var password: String
        /// The account name for Apple Remote Desktop authentication (macOS
        /// Screen Sharing); VNC authentication has none.
        var username: String = ""
        var shared: Bool
        var timeout: TimeInterval = 15
        /// Overrides the transport the client talks on — the SSH-tunnel
        /// path and tests hand one in.
        var transport: VNCTransport?
    }

    /// What the session task and the input calls share.
    private struct State {
        var transport: VNCTransport?
        var task: Task<Void, Never>?
        var stopped = false
        var buttonMask: UInt8 = 0
    }

    private let configuration: Configuration
    private weak let delegate: VNCRFBClientDelegate?
    private let framebuffer = VNCFramebuffer()
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(configuration: Configuration, delegate: VNCRFBClientDelegate) {
        self.configuration = configuration
        self.delegate = delegate
    }

    // MARK: - Lifecycle

    /// Starts the session in the background.
    func start() {
        let task = Task { await run() }
        state.withLock { $0.task = task }
    }

    /// Ends the session: the task is cancelled and the transport closed, so
    /// a pending receive wakes and the task exits.
    func stop() {
        let (task, transport) = state.withLock { state in
            state.stopped = true
            return (state.task, state.transport)
        }
        task?.cancel()
        transport?.close()
    }

    private var isStopped: Bool {
        state.withLock { $0.stopped }
    }

    private func report(phase: RemoteDesktopPhase, hint: String? = nil) {
        delegate?.client(self, didChangePhase: phase, hint: hint)
    }

    // MARK: - The session

    /// The session; `internal` so tests can await it over a scripted
    /// memory transport.
    func run() async {
        report(phase: .connecting("Reaching \(configuration.host)"), hint: "Connecting…")
        do {
            let transport: VNCTransport = if let transport = configuration.transport {
                transport
            } else {
                try await VNCConnection.connect(host: configuration.host, port: configuration.port, timeout: configuration.timeout)
            }
            let alreadyStopped = state.withLock { state in
                state.transport = transport
                return state.stopped
            }
            if alreadyStopped {
                transport.close()
                return
            }
            let reader = VNCReader(transport)
            let inflater = try VNCInflateStream()
            let desktopName = try await handshake(reader: reader, transport: transport)
            report(phase: .connected, hint: nil)
            try await readLoop(reader: reader, inflater: inflater, desktopName: desktopName)
            if !isStopped {
                report(phase: .closed("The server closed the connection."))
            }
        } catch let error as RemoteDesktopFailure {
            report(phase: .failed(error.message))
        } catch let error as VNCStreamError {
            if isStopped { return }
            switch error {
            case .endOfStream:
                report(phase: .closed("The server closed the connection."))
            case let .failed(reason):
                report(phase: .failed(reason))
            }
        } catch let error as VNCDecodeError {
            report(phase: .failed("The server sent data this client cannot read (\(describe(error)))."))
        } catch {
            if !isStopped {
                report(phase: .failed(error.localizedDescription))
            }
        }
    }

    private func describe(_ error: VNCDecodeError) -> String {
        switch error {
        case let .unsupportedEncoding(encoding): "encoding \(encoding)"
        case let .malformed(reason): reason
        }
    }

    // MARK: Handshake

    /// Runs the handshake through ServerInit; returns the desktop name.
    private func handshake(reader: VNCReader, transport: VNCTransport) async throws -> String {
        // Version banner.
        let banner = try await reader.read(exactly: 12)
        guard let version = VNCWire.parseBanner(banner) else {
            throw RemoteDesktopFailure("The server is not speaking RFB.")
        }
        // Answer the best version both support: 3.3 only if the server is
        // that old; otherwise 3.8 (the failure-reason string exists only
        // on 3.8).
        let answerMinor = version.minor < 8 ? version.minor : 8
        transport.send(VNCWire.banner(major: 3, minor: answerMinor))
        let protocol38 = answerMinor >= 8

        // Security negotiation.
        report(phase: .authenticating, hint: "Authenticating…")
        var offered: [UInt8] = []
        if version.minor == 3 {
            // 3.3 sends one u32 type directly; 0 means the connection is
            // refused outright and a reason string follows.
            let type = try await reader.read(exactly: 4).readU32BE(at: 0).clampedToUInt8()
            if type == 0 {
                let reason = try await readReasonString(reader)
                throw RemoteDesktopFailure(reason ?? "The server refused the connection.")
            }
            offered = [type]
        } else {
            let count = Int(try await reader.read(exactly: 1)[0])
            guard count > 0 else {
                let reason = try await readReasonString(reader)
                throw RemoteDesktopFailure(reason ?? "The server refused the connection.")
            }
            offered = Array(try await reader.read(exactly: count))
        }

        let selected = try Self.chooseSecurityType(
            from: offered,
            username: configuration.username,
            password: configuration.password
        )

        if version.minor != 3 {
            transport.send(Data([selected]))
        }

        switch selected {
        case VNCWire.SecurityType.vncAuth.rawValue:
            let challenge = Array(try await reader.read(exactly: 16))
            guard let response = VNCDES.encryptChallenge(challenge, password: configuration.password) else {
                throw RemoteDesktopFailure("Could not answer the VNC authentication challenge.")
            }
            transport.send(Data(response))
        case VNCWire.SecurityType.appleRemoteDesktop.rawValue:
            let parameters = try await VNCAppleAuth.readParameters(from: reader)
            let response = try VNCAppleAuth.response(
                to: parameters,
                username: configuration.username,
                password: configuration.password
            )
            transport.send(response)
        default:
            break
        }

        // SecurityResult: u32, 0 on success. For 3.8 a failure carries a
        // reason string; for 3.3 and 3.7 it does not.
        let result = try await reader.read(exactly: 4).readU32BE(at: 0)
        if result != 0 {
            let reason = protocol38 ? try await readReasonString(reader) : nil
            throw RemoteDesktopFailure(reason ?? "The VNC server rejected the credentials.")
        }

        // ClientInit / ServerInit.
        transport.send(VNCWire.clientInit(shared: configuration.shared))
        report(phase: .connecting("Negotiating the framebuffer"), hint: "Negotiating…")
        // width(2) height(2) pixelformat(16) nameLen(4) + name
        var initData = try await reader.read(exactly: 24)
        let nameLength = Int(initData.readU32BE(at: 20))
        guard nameLength <= 64 * 1024 else {
            throw RemoteDesktopFailure("The server sent a malformed init message.")
        }
        initData.append(try await reader.read(exactly: nameLength))
        guard let serverInit = VNCWire.parseServerInit(data: initData) else {
            throw RemoteDesktopFailure("The server sent a malformed init message.")
        }
        guard serverInit.pixelFormat.translator() != nil else {
            throw RemoteDesktopFailure("The server's pixel format (\(serverInit.pixelFormat.bitsPerPixel)bpp, depth \(serverInit.pixelFormat.depth)) is unsupported.")
        }
        try resizeFramebuffer(width: serverInit.width, height: serverInit.height)

        // From here on the server emits `clientRequested` pixels.
        transport.send(VNCWire.setPixelFormat(.clientRequested))
        transport.send(VNCWire.setEncodings(VNCWire.clientEncodings))
        requestUpdate(incremental: false)
        delegate?.client(self, didUpdateFrame: nil, size: framebuffer.size, desktopName: serverInit.desktopName)
        return serverInit.desktopName
    }

    /// The strongest security type both sides support. With credentials
    /// configured the client authenticates or fails — it never takes
    /// `none`, so a man in the middle cannot strip authentication by
    /// offering only that. Apple authentication (DH + AES) beats the VNC
    /// password (DES challenge) whenever there is a user name to give.
    static func chooseSecurityType(from offered: [UInt8], username: String, password: String) throws -> UInt8 {
        let none = VNCWire.SecurityType.none.rawValue
        let vncAuth = VNCWire.SecurityType.vncAuth.rawValue
        let apple = VNCWire.SecurityType.appleRemoteDesktop.rawValue
        guard !password.isEmpty else {
            if offered.contains(none) { return none }
            if offered.contains(apple), !username.isEmpty {
                throw RemoteDesktopFailure("The Mac asks for the password of \(username). Set one on the server, or on its identity.")
            }
            if offered.contains(vncAuth) {
                throw RemoteDesktopFailure("The VNC server asks for a password. Set one on the server, or on the identity it falls back to.")
            }
            if offered.contains(apple) {
                throw RemoteDesktopFailure("The Mac asks for a user name and password. Set the VNC user name on the server, or give it an identity.")
            }
            throw RemoteDesktopFailure("The server offers no supported security type (\(offered.map(String.init).joined(separator: ", "))).")
        }
        if offered.contains(apple), !username.isEmpty { return apple }
        if offered.contains(vncAuth) { return vncAuth }
        if offered.contains(apple) {
            throw RemoteDesktopFailure("The Mac asks for a user name with the password. Set the VNC user name on the server, or give it an identity.")
        }
        if offered.contains(none) {
            throw RemoteDesktopFailure("A password is set for this server, but it offered to connect without authentication. Refusing, as that is how a man in the middle would strip it; clear the password if the server really has none.")
        }
        throw RemoteDesktopFailure("The server offers no supported security type (\(offered.map(String.init).joined(separator: ", "))).")
    }

    /// A 3.8 reason string: u32 length + UTF-8 text; 3.3/3.7 send nothing.
    private func readReasonString(_ reader: VNCReader) async throws -> String? {
        let length = Int(try await reader.read(exactly: 4).readU32BE(at: 0))
        guard length > 0, length < 64 * 1024 else { return nil }
        return String(data: try await reader.read(exactly: length), encoding: .utf8)
    }

    // MARK: Read loop

    private func readLoop(reader: VNCReader, inflater: VNCInflateStream, desktopName: String) async throws {
        let format = VNCPixelFormat.clientRequested
        let context = VNCDecoders.Context(
            framebuffer: framebuffer,
            pixelTranslator: format.translator() ?? { _, _ in 0xFFFF_00FF },
            bytesPerPixel: format.bytesPerPixel,
            cpixelByteCount: format.cpixelByteCount,
            cpixelPadsAtEnd: !format.bigEndian,
            zlib: inflater
        )
        while !isStopped {
            let type = try await reader.read(exactly: 1)[0]
            switch VNCWire.ServerMessageType(rawValue: type) {
            case .framebufferUpdate:
                try await handleUpdate(reader: reader, context: context, desktopName: desktopName)
            case .setColourMapEntries:
                // pad(1) firstColor(2) count(2) + count * 6 bytes
                let header = try await reader.read(exactly: 5)
                let count = Int(header.readU16BE(at: 3))
                _ = try await reader.read(exactly: count * 6)
            case .bell:
                break
            case .serverCutText:
                _ = try await reader.read(exactly: 3) // padding
                let length = Int(try await reader.read(exactly: 4).readU32BE(at: 0))
                guard length < 16 * 1024 * 1024 else {
                    throw VNCDecodeError.malformed("clipboard of \(length) bytes")
                }
                let text = String(data: try await reader.read(exactly: length), encoding: .isoLatin1) ?? ""
                delegate?.client(self, didReceiveClipboard: text)
            case nil:
                // Unknown message: there is no way to know its length, so
                // the stream is unrecoverable.
                throw RemoteDesktopFailure("The server sent an unknown message type \(type).")
            }
        }
    }

    private func resizeFramebuffer(width: Int, height: Int) throws {
        guard width <= VNCFramebuffer.maximumDimension, height <= VNCFramebuffer.maximumDimension else {
            throw RemoteDesktopFailure("The remote desktop is too large (\(width)×\(height)).")
        }
        framebuffer.resize(width: width, height: height)
    }

    private func handleUpdate(reader: VNCReader, context: VNCDecoders.Context, desktopName: String) async throws {
        _ = try await reader.read(exactly: 1) // padding
        let count = Int(try await reader.read(exactly: 2).readU16BE(at: 0))
        var sizeChanged = false
        for _ in 0 ..< count {
            let headerData = try await reader.read(exactly: VNCWire.RectangleHeader.wireLength)
            guard let header = VNCWire.RectangleHeader(wire: headerData) else {
                throw RemoteDesktopFailure("The server sent a malformed rectangle.")
            }
            switch VNCWire.Encoding(rawValue: header.encoding) {
            case .desktopSize:
                try resizeFramebuffer(width: header.width, height: header.height)
                sizeChanged = true
            case .cursor:
                let cursor = try await VNCDecoders.decodeCursor(header, from: reader, context: context)
                delegate?.client(self, didUpdateCursor: cursor)
            default:
                try await VNCDecoders.decode(header, from: reader, context: context)
            }
        }
        let image = framebuffer.makeImage()
        delegate?.client(self, didUpdateFrame: image, size: framebuffer.size, desktopName: sizeChanged ? desktopName : nil)
        requestUpdate(incremental: true)
    }

    // MARK: - Outbound messages (called from the main actor)

    /// Queues `data` once connected; dropped before that.
    private func send(_ data: Data) {
        state.withLock { $0.transport }?.send(data)
    }

    func requestUpdate(incremental: Bool) {
        let size = framebuffer.size
        guard size.width > 0, size.height > 0 else { return }
        send(VNCWire.framebufferUpdateRequest(
            incremental: incremental, x: 0, y: 0,
            width: UInt16(min(Int(size.width), Int(UInt16.max))),
            height: UInt16(min(Int(size.height), Int(UInt16.max)))
        ))
    }

    /// The RFB button bit for a mouse button.
    private func buttonBit(_ button: MouseButton) -> UInt8 {
        switch button {
        case .left: return 1 << 0
        case .middle: return 1 << 1
        case .right: return 1 << 2
        // Wheels go through sendScroll; extra buttons have no RFB type.
        case .back, .forward: return 0
        }
    }

    /// Normalized view coordinates -> framebuffer pixel coordinates.
    private func pixelPoint(normalizedX: Double, normalizedY: Double) -> (x: UInt16, y: UInt16) {
        let size = framebuffer.size
        let x = UInt16((normalizedX * Double(size.width)).clamped(to: 0 ... Double(max(size.width - 1, 0))))
        let y = UInt16((normalizedY * Double(size.height)).clamped(to: 0 ... Double(max(size.height - 1, 0))))
        return (x, y)
    }

    func pointerMoved(normalizedX: Double, normalizedY: Double) {
        let point = pixelPoint(normalizedX: normalizedX, normalizedY: normalizedY)
        let mask = state.withLock { $0.buttonMask }
        send(VNCWire.pointerEvent(buttonMask: mask, x: point.x, y: point.y))
    }

    func pointerButton(_ button: MouseButton, isDown: Bool, normalizedX: Double, normalizedY: Double) {
        let point = pixelPoint(normalizedX: normalizedX, normalizedY: normalizedY)
        let bit = buttonBit(button)
        let mask = state.withLock { state in
            if isDown { state.buttonMask |= bit } else { state.buttonMask &= ~bit }
            return state.buttonMask
        }
        send(VNCWire.pointerEvent(buttonMask: mask, x: point.x, y: point.y))
    }

    /// A wheel event is a button press-release pair per tick, coalesced into a single write.
    func scrolled(deltaX: Double, deltaY: Double, normalizedX: Double, normalizedY: Double) {
        let point = pixelPoint(normalizedX: normalizedX, normalizedY: normalizedY)
        let mask = state.withLock { $0.buttonMask }

        var batch = Data()
        func appendWheelTicks(_ delta: Double, upBit: UInt8, downBit: UInt8) {
            let ticks = min(Int(abs(delta).rounded()), 10)
            let bit: UInt8 = delta > 0 ? upBit : downBit
            for _ in 0 ..< ticks {
                batch.append(VNCWire.pointerEvent(buttonMask: mask | bit, x: point.x, y: point.y))
                batch.append(VNCWire.pointerEvent(buttonMask: mask, x: point.x, y: point.y))
            }
        }
        // RFB: bit3=scroll up, bit4=down, bit5=left, bit6=right.
        appendWheelTicks(deltaY, upBit: 1 << 3, downBit: 1 << 4)
        appendWheelTicks(deltaX, upBit: 1 << 6, downBit: 1 << 5)
        if !batch.isEmpty {
            send(batch)
        }
    }

    func keyEvent(keyCode: UInt16, keySym: UInt32?, characters: String, isDown: Bool) {
        let sym = keySym ?? VNCKeySyms.keySym(forKeyCode: keyCode, characters: characters)
        guard let sym else { return }
        send(VNCWire.keyEvent(down: isDown, keySym: sym))
    }

    func typeText(_ text: String) {
        for scalar in text.unicodeScalars {
            guard let sym = VNCKeySyms.keySym(forCharacter: String(scalar)) else { continue }
            send(VNCWire.keyEvent(down: true, keySym: sym))
            send(VNCWire.keyEvent(down: false, keySym: sym))
        }
    }

    func setClipboard(_ text: String) {
        send(VNCWire.clientCutText(text))
    }
}

private extension UInt32 {
    func clampedToUInt8() -> UInt8 {
        UInt8(Swift.min(self, UInt32(UInt8.max)))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
