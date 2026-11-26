//
//  UURemoteControlProtocol.swift
//  RayonModule
//
//  The protobuf envelope and JSON input codec for the UU Remote
//  CONTROL_DATA_CHANNEL. Mirrors /tmp/uu-refs/uu-remote-linux/src/control_protocol.rs
//  and /tmp/uu-refs/uurc-web/shared/src/streamer/controlChannelProtocol.ts.
//

import CoreGraphics
import Foundation

/// Envelope Message field numbers on CONTROL_DATA_CHANNEL.
public enum UUControlField {
    public static let sequence: UInt32 = 1
    public static let timestamp: UInt32 = 2
    public static let simpleAction: UInt32 = 3
    public static let screenSources: UInt32 = 7
    public static let captureChange: UInt32 = 8
    public static let romMessage: UInt32 = 10
    public static let sendToRom: UInt32 = 11
    public static let reportError: UInt32 = 12
    public static let systemStateChange: UInt32 = 15
    public static let codecNegotiation: UInt32 = 18
    public static let rpcRequest: UInt32 = 21
    public static let rpcResponse: UInt32 = 22
    public static let portMappingFrame: UInt32 = 27
}

/// SimpleAction.action values (official ActionType table, 28 entries).
public enum UUSimpleActionType {
    public static let echoRequest: UInt64 = 0
    public static let echoResponse: UInt64 = 1
    public static let showDesktop: UInt64 = 2
    public static let showWindows: UInt64 = 3
    public static let captureDesktop: UInt64 = 4
    public static let captureWindow: UInt64 = 5
    public static let captureMumu: UInt64 = 6
    public static let stopCapture: UInt64 = 7
    public static let restartCapture: UInt64 = 8
    public static let rebootSystem: UInt64 = 9
    public static let lockSystem: UInt64 = 10
    public static let keyToggle: UInt64 = 11
    public static let shutdownSystem: UInt64 = 12
    public static let showTaskmgr: UInt64 = 13
    public static let muteSystem: UInt64 = 14
    public static let autoUnlockSystem: UInt64 = 15
    public static let muteRestore: UInt64 = 16
    public static let mutePermanent: UInt64 = 17
    public static let muteTemporary: UInt64 = 18
    public static let setAutoLock: UInt64 = 19
    public static let stopAcquireUpdate: UInt64 = 20
    public static let quitCapture: UInt64 = 21
    public static let acquireSystemInfo: UInt64 = 22
    public static let microphoneOpened: UInt64 = 23
    public static let microphoneClosed: UInt64 = 24
    public static let speakerOpened: UInt64 = 25
    public static let speakerClosed: UInt64 = 26
    public static let needRestartUserapp: UInt64 = 27

    public static func name(of action: UInt64) -> String? {
        let names: [UInt64: String] = [
            echoRequest: "echo_request", echoResponse: "echo_response",
            showDesktop: "show_desktop", showWindows: "show_windows",
            captureDesktop: "capture_desktop", captureWindow: "capture_window",
            captureMumu: "capture_mumu", stopCapture: "stop_capture",
            restartCapture: "restart_capture", rebootSystem: "reboot_system",
            lockSystem: "lock_system", keyToggle: "key_toggle",
            shutdownSystem: "shutdown_system", showTaskmgr: "show_taskmgr",
            muteSystem: "mute_system", autoUnlockSystem: "auto_unlock_system",
            muteRestore: "mute_restore", mutePermanent: "mute_permanent",
            muteTemporary: "mute_temporary", setAutoLock: "set_auto_lock",
            stopAcquireUpdate: "stop_acquire_update", quitCapture: "quit_capture",
            acquireSystemInfo: "acquire_system_info",
            microphoneOpened: "microphone_opened", microphoneClosed: "microphone_closed",
            speakerOpened: "speaker_opened", speakerClosed: "speaker_closed",
            needRestartUserapp: "need_restart_userapp",
        ]
        return names[action]
    }
}

/// FeatureFlag fields inside SimpleAction.field4.
public enum UUFeatureFlagTag {
    public static let captureSetting: Int = 1
    public static let simpleAction: Int = 2
    public static let systemMetrics: Int = 3
    public static let privateScreen: Int = 4
    public static let updateAcquire: Int = 5
    public static let fileTransferFTP: Int = 6
    public static let fileTransferFTP2: Int = 7
    public static let clipboard: Int = 8
    public static let qosStat: Int = 9
    public static let mumuControl: Int = 10
    public static let virtualMouseDevice: Int = 11
}

/// SimpleAction.field4 FeatureFlag values the desktop controller advertises.
public enum UUControllerFeatureFlag {
    public static let captureSetting: Int32 = 6
    public static let simpleAction: Int32 = 2
    public static let systemMetrics: Int32 = 1
    public static let privateScreen: Int32 = 4
    public static let updateAcquire: Int32 = 0
    public static let fileTransferFTP: Int32 = 2
    public static let fileTransferFTP2: Int32 = 2
    public static let clipboard: Int32 = 3
    public static let qosStat: Int32 = 1
    public static let mumuControl: Int32 = 0
    public static let virtualMouseDevice: Int32 = 0
}

/// Encodes/decodes the CONTROL_DATA_CHANNEL envelope and input JSON.
public enum UUControlProtocol {
    /// Wraps a body message into the standard envelope `{1:seq, 2:ts, <which>}`.
    public static func envelope(sequence: UInt64, timestamp: UInt64, fieldNumber: UInt32, body: Data) -> Data {
        var out = Data()
        if sequence != 0 { UUProtobufWriter.pushVarintField(Int(UUControlField.sequence), sequence, into: &out) }
        if timestamp != 0 { UUProtobufWriter.pushVarintField(Int(UUControlField.timestamp), timestamp, into: &out) }
        UUProtobufWriter.pushMessageField(Int(fieldNumber), body, into: &out)
        return out
    }

    /// Builds a SimpleAction body: `{1:action, 2:argsJson, 4:FeatureFlag}`.
    public static func simpleAction(action: UInt64, argsJSON: String, featureFlags: Data? = nil) -> Data {
        var out = Data()
        UUProtobufWriter.pushVarintField(1, action, into: &out)
        let args = Data(argsJSON.utf8)
        if !args.isEmpty { UUProtobufWriter.pushBytesField(2, args, into: &out) }
        if let featureFlags, !featureFlags.isEmpty { UUProtobufWriter.pushMessageField(4, featureFlags, into: &out) }
        return out
    }

    /// Verified protobuf echo-response envelope for the host's echo request.
    public static func echoResponseEnvelope(sequence: UInt64, timestamp: UInt64, requestSequence: UInt64, clipboardEnabled: Bool) -> Data {
        var action = Data()
        UUProtobufWriter.pushVarintField(1, UUSimpleActionType.echoResponse, into: &action)
        let args = #"{"seq":\#(requestSequence)}"#.data(using: .utf8)!
        UUProtobufWriter.pushBytesField(2, args, into: &action)
        var flags = Data()
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.captureSetting, UUControllerFeatureFlag.captureSetting, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.simpleAction, UUControllerFeatureFlag.simpleAction, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.systemMetrics, UUControllerFeatureFlag.systemMetrics, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.fileTransferFTP, 2, into: &flags)
        if clipboardEnabled {
            UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.clipboard, UUControllerFeatureFlag.clipboard, into: &flags)
        }
        UUProtobufWriter.pushMessageField(4, flags, into: &action)
        return envelope(sequence: sequence, timestamp: timestamp, fieldNumber: UUControlField.simpleAction, body: action)
    }

    /// The heartbeat echo request sent every 100 ms once the channel opens.
    /// Flag versions mirror the upstream viewer's `feature_flag` pairs
    /// (`UUViewerFeatureFlags`): private_screen is 2, not 4.
    public static func echoRequestEnvelope(sequence: UInt64, timestamp: UInt64) -> Data {
        var action = Data()
        UUProtobufWriter.pushVarintField(1, UUSimpleActionType.echoRequest, into: &action)
        var flags = Data()
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.captureSetting, UUViewerFeatureFlags.captureSetting, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.simpleAction, UUViewerFeatureFlags.simpleAction, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.systemMetrics, UUViewerFeatureFlags.systemMetrics, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.privateScreen, UUViewerFeatureFlags.privateScreen, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.fileTransferFTP, UUViewerFeatureFlags.fileTransferFTP, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.fileTransferFTP2, UUViewerFeatureFlags.fileTransferFTP2, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.clipboard, UUViewerFeatureFlags.clipboard, into: &flags)
        UUProtobufWriter.pushInt32Field(UUFeatureFlagTag.qosStat, UUViewerFeatureFlags.qosStat, into: &flags)
        UUProtobufWriter.pushMessageField(4, flags, into: &action)
        return envelope(sequence: sequence, timestamp: timestamp, fieldNumber: UUControlField.simpleAction, body: action)
    }

    /// RPC request envelope `{21:RpcRequest{1:header{1:requestId},<case>}}`.
    public static func rpcRequest(requestID: UInt64, bodyField: UInt32, body: Data) -> Data {
        var header = Data()
        UUProtobufWriter.pushVarintField(1, requestID, into: &header)
        var request = Data()
        UUProtobufWriter.pushMessageField(1, header, into: &request)
        UUProtobufWriter.pushMessageField(Int(bodyField), body, into: &request)
        return envelope(sequence: requestID, timestamp: UInt64(Date().timeIntervalSince1970 * 1000), fieldNumber: UUControlField.rpcRequest, body: request)
    }

    /// RpcRequest case 15 `SendVideoTrack {1: repeated video_track_index}`:
    /// the tracks the viewer has, which the host may stream screens on.
    public static func sendVideoTrackRequest(requestID: UInt64, tracks: [Int] = []) -> Data {
        var body = Data()
        for track in tracks { UUProtobufWriter.pushInt32Field(1, Int32(clamping: track), into: &body) }
        return rpcRequest(requestID: requestID, bodyField: 15, body: body)
    }

    /// RpcRequest case 2 `CaptureSettingRequest`, whole, as the official
    /// viewer sends it on every change (openuuyc `capture_setting_request`):
    /// {1: fps tier, 2: quality, 3: cursor_capture, 4: screen_id -2 (the
    /// session's tracks, no monitor), 5/6: resolution -1 (unchanged), 7:
    /// chroma (1 4:2:0, 3 4:4:4), 8: custom bit rate, 9: dpi 0, 10:
    /// resolution type 1, 11: hdr, 12: auto quality, 13: codec (1 H.264,
    /// 2 H.265), 14/15: largest size we decode, 18: fps the viewer shows}.
    /// Zeros are left off, as protobuf does.
    public static func captureSettingRequest(
        requestID: UInt64,
        settings: RemoteDesktopStreamSettings,
        codecType: Int32,
        fpsCount: Int32,
        cursorCapture: Bool
    ) -> Data {
        var body = Data()
        func put(_ field: Int, _ value: Int32) {
            if value != 0 { UUProtobufWriter.pushInt32Field(field, value, into: &body) }
        }
        put(1, Int32(UUFpsTier.encode(rawFPS: settings.fps)))
        put(2, Int32(settings.quality))
        put(3, cursorCapture ? 1 : 0)
        put(4, -2)
        put(5, -1)
        put(6, -1)
        put(7, Int32(settings.trueColor ? UUChromaFormat.c444 : UUChromaFormat.c420))
        put(10, 1)
        put(12, Int32(RemoteDesktopStreamSettings.qualityHD))
        put(13, codecType)
        put(14, 3840)
        put(15, 2160)
        put(18, fpsCount)
        return rpcRequest(requestID: requestID, bodyField: 2, body: body)
    }

    /// An RpcResponse (field 22) `{1: {1: request_id}, 2: CaptureSettingResponse
    /// {1: repeated Error {1: code, 2: message, 3: detail}}}`: the request
    /// it answers and its errors (none: applied). Nil for anything else.
    public static func decodeCaptureSettingResponse(_ data: Data) -> (requestID: UInt64, errors: [(code: Int, message: String, detail: String)])? {
        guard let inbound = decodeInbound(data),
              inbound.field.number == UUControlField.rpcResponse,
              case let .bytes(rpc) = inbound.field.value,
              let fields = try? UUWire.decode(rpc)
        else { return nil }
        var requestID: UInt64 = 0
        var body: Data?
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .bytes(header)):
                for item in (try? UUWire.decode(header)) ?? [] {
                    if item.number == 1, case let .varint(v) = item.value { requestID = v }
                }
            case (2, let .bytes(b)): body = b
            default: break
            }
        }
        // An answer with no errors leaves its empty body off the wire, which
        // is indistinguishable from another RpcResponse's unless the other
        // cases are ruled out: a response carrying a clipboard case (5 rich,
        // 6 text-change) is the clipboard's, never a capture answer.
        let carriesClipboardCase = fields.contains { $0.number == 5 || $0.number == 6 }
        guard !carriesClipboardCase, requestID != 0 || body != nil,
              let parts = try? UUWire.decode(body ?? Data()) else { return nil }
        var errors: [(code: Int, message: String, detail: String)] = []
        for part in parts where part.number == 1 {
            guard case let .bytes(b) = part.value, let items = try? UUWire.decode(b) else { continue }
            var code = 0
            var message = ""
            var detail = ""
            for item in items {
                switch (item.number, item.value) {
                case (1, let .varint(v)): code = v.int32Value
                case (2, let .bytes(text)): message = String(decoding: text, as: UTF8.self)
                case (3, let .bytes(text)): detail = String(decoding: text, as: UTF8.self)
                default: break
                }
            }
            errors.append((code, message, detail))
        }
        return (requestID, errors)
    }

    // MARK: - JSON input on CONTROL_DATA_CHANNEL

    /// Wire values per upstream `STREAMER_MOUSE_BUTTON_CODES`:
    /// primary=1, secondary=2, tertiary=4, back=8, forward=16.
    public enum Button: Int32 {
        case left = 1
        case right = 2
        case middle = 4
        case back = 8
        case forward = 16
    }

    /// `screenID` is the screen the position is on: without it the host
    /// puts the pointer on whichever screen it captured last, which on a
    /// host with several is not always the one in view.
    public static func mouseMoveAbsolute(x: Double, y: Double, screenID: Int? = nil) -> Data {
        // Mac hosts take normalized 0...1 axes (clamped, like upstream's
        // `normalizeAbsolutePointerAxis`). What is no number becomes 0
        // rather than a bare `nan` the host's JSON cannot read.
        let cx = x.isFinite ? min(1, max(0, x)) : 0
        let cy = y.isFinite ? min(1, max(0, y)) : 0
        if let screenID {
            return #"{"action":"mouse_move_absolute","screen_id":\#(screenID),"abs_x":\#(cx),"abs_y":\#(cy)}"#.data(using: .utf8)!
        }
        return #"{"action":"mouse_move_absolute","abs_x":\#(cx),"abs_y":\#(cy)}"#.data(using: .utf8)!
    }

    public static func mouseMoveRelative(dx: Int32, dy: Int32) -> Data {
        #"{"action":"mouse_move_relative","delta_x":\#(dx),"delta_y":\#(dy)}"#.data(using: .utf8)!
    }

    public static func mouseButton(_ button: Button, isDown: Bool) -> Data {
        let action = isDown ? "mouse_press" : "mouse_release"
        return #"{"action":"\#(action)","button":\#(button.rawValue)}"#.data(using: .utf8)!
    }

    public static func mouseClick(_ button: Button) -> Data {
        #"{"action":"mouse_click","button":\#(button.rawValue)}"#.data(using: .utf8)!
    }

    public static func mouseScroll(dx: Int32, dy: Int32) -> Data {
        #"{"action":"mouse_scroll","delta_x":\#(dx),"delta_y":\#(dy)}"#.data(using: .utf8)!
    }

    public static func keyPress(key: Int32, isDown: Bool, windowsTarget: Bool = false) -> Data {
        let action = isDown ? "kbd_press" : "kbd_release"
        var json = #"{"action":"\#(action)","key":\#(key)}"#
        if windowsTarget { json = json.dropLast() + #","interrept":true}"# }
        return json.data(using: .utf8)!
    }

    public static func keyClick(key: Int32) -> Data {
        #"{"action":"kbd_click","key":\#(key)}"#.data(using: .utf8)!
    }

    public static func textInput(_ text: String) -> Data {
        // JSON-escape via the serializer: quotes, backslashes and control
        // characters in `text` must not corrupt the wire JSON.
        (try? JSONSerialization.data(withJSONObject: ["action": "text_input", "content": text])) ?? Data()
    }

    public static func keyboardHeartbeat() -> Data {
        #"{"heartbeat":"kbd_heartbeat"}"#.data(using: .utf8)!
    }

    /// Decodes the CONTROL_DATA_CHANNEL envelope `{1:seq, 2:ts, <which>}` into
    /// a typed inbound message, or `nil` for malformed payloads.
    public static func decodeInbound(_ data: Data) -> Inbound? {
        guard let fields = try? UUWire.decode(data) else { return nil }
        var sequence: UInt64 = 0
        var timestamp: UInt64 = 0
        var body: [UUWireField] = []
        for field in fields {
            switch field.number {
            case UUControlField.sequence:
                if case let .varint(v) = field.value { sequence = v }
            case UUControlField.timestamp:
                if case let .varint(v) = field.value { timestamp = v }
            default:
                body.append(field)
            }
        }
        guard let first = body.first else { return nil }
        return Inbound(sequence: sequence, timestamp: timestamp, field: first)
    }

    public struct Inbound: Sendable {
        public var sequence: UInt64
        public var timestamp: UInt64
        public var field: UUWireField
    }

    /// Decodes a SimpleAction body (inside field 3).
    public static func decodeSimpleAction(_ data: Data) -> (action: UInt64, argsJSON: String?, featureFlags: UUFeatureFlags)? {
        guard let fields = try? UUWire.decode(data) else { return nil }
        var action: UInt64 = 0
        var args: String?
        var flags = UUFeatureFlags()
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .varint(v)): action = v
            case (2, let .bytes(b)): args = String(data: b, encoding: .utf8)
            case (4, let .bytes(b)): flags = UUFeatureFlags(decoding: b)
            default: break
            }
        }
        return (action, args, flags)
    }

    /// Decodes ScreenSources (field 7): `{1: repeated Screen, 2:
    /// current_screen_id}`, where Screen is `{1: id, 2: fps, 3: repeated
    /// WinRect resolutions, 4: WinRect current_resolution, 5: screen_type
    /// (1 = UU virtual screen), 7: is_primary, 10: display_name, 12:
    /// video_track_index}` and WinRect `{1: left, 2: top, 3: width, 4:
    /// height, 5: pixel_width, 6: pixel_height}`.
    ///
    /// Zero is never on the wire: an absent current id or track index is 0
    /// once the host says any other screen's, and unknown (nil) otherwise.
    public static func decodeScreenSources(_ data: Data) -> (displays: [RemoteDisplayInfo], currentID: Int?) {
        guard let fields = try? UUWire.decode(data) else { return ([], nil) }
        var displays: [(display: RemoteDisplayInfo, trackSaid: Bool)] = []
        var currentID: Int?
        var anyTrackSaid = false
        for field in fields {
            if field.number == 2, case let .varint(v) = field.value { currentID = v.int32Value }
            guard field.number == 1, case let .bytes(b) = field.value,
                  let sub = try? UUWire.decode(b) else { continue }
            var display = RemoteDisplayInfo(id: 0)
            var trackSaid = false
            var name = ""
            var current: (width: Int, height: Int)?
            var listed: (width: Int, height: Int)?
            for item in sub {
                switch (item.number, item.value) {
                case (1, let .varint(v)): display.id = v.int32Value
                case (2, let .varint(v)): display.fps = v.int32Value
                case (3, let .bytes(rect)): listed = listed ?? winRectSize(rect)
                case (4, let .bytes(rect)): current = winRectSize(rect)
                case (5, let .varint(v)): display.isVirtual = v == 1
                case (7, let .varint(v)): display.isPrimary = v != 0
                case (10, let .bytes(b)): name = String(data: b, encoding: .utf8) ?? ""
                case (12, let .varint(v)):
                    // -1: the host streams this screen on no track now.
                    let index = v.int32Value
                    display.videoTrackIndex = index >= 0 ? index : nil
                    trackSaid = true
                    anyTrackSaid = true
                default: break
                }
            }
            if let size = current ?? listed { (display.width, display.height) = size }
            display.name = name.isEmpty ? "Display \(display.id)" : name
            displays.append((display, trackSaid))
        }
        if anyTrackSaid {
            for index in displays.indices where !displays[index].trackSaid {
                displays[index].display.videoTrackIndex = 0
            }
        }
        if currentID == nil, displays.contains(where: { $0.display.id == 0 }) { currentID = 0 }
        return (displays.map(\.display), currentID)
    }

    /// A WinRect's size in pixels, or in points when it gives no pixels.
    private static func winRectSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let fields = try? UUWire.decode(data) else { return nil }
        var points = (width: 0, height: 0)
        var pixels = (width: 0, height: 0)
        for field in fields {
            guard case let .varint(v) = field.value else { continue }
            switch field.number {
            case 3: points.width = v.int32Value
            case 4: points.height = v.int32Value
            case 5: pixels.width = v.int32Value
            case 6: pixels.height = v.int32Value
            default: break
            }
        }
        if pixels.width > 0, pixels.height > 0 { return pixels }
        if points.width > 0, points.height > 0 { return points }
        return nil
    }

    /// SimpleAction `restart_capture` (8) or `stop_capture` (7) for one
    /// screen: the official viewer starts a screen's stream with the first
    /// and ends it with the second, as it opens and closes the screen's tab.
    public static func captureScreen(_ screenID: Int, start: Bool, sequence: UInt64) -> Data {
        envelope(
            sequence: sequence,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            fieldNumber: UUControlField.simpleAction,
            body: simpleAction(
                action: start ? UUSimpleActionType.restartCapture : UUSimpleActionType.stopCapture,
                argsJSON: #"{"screen_id":\#(screenID)}"#
            )
        )
    }

    /// RpcRequest case 12 `CreateVirtualDisplay {1: repeated
    /// ScreenResolution{1: width, 2: height} local_resolution, 2: count}`:
    /// the host adds a UU virtual screen of that size.
    public static func createVirtualDisplay(requestID: UInt64, width: Int, height: Int) -> Data {
        var resolution = Data()
        UUProtobufWriter.pushInt32Field(1, Int32(clamping: width), into: &resolution)
        UUProtobufWriter.pushInt32Field(2, Int32(clamping: height), into: &resolution)
        var body = Data()
        UUProtobufWriter.pushMessageField(1, resolution, into: &body)
        UUProtobufWriter.pushInt32Field(2, 1, into: &body)
        return rpcRequest(requestID: requestID, bodyField: 12, body: body)
    }

    /// RpcRequest case 13 `RemoveVirtualDisplay {1: repeated screen_id}`.
    public static func removeVirtualDisplay(requestID: UInt64, screenID: Int) -> Data {
        var body = Data()
        UUProtobufWriter.pushInt32Field(1, Int32(clamping: screenID), into: &body)
        return rpcRequest(requestID: requestID, bodyField: 13, body: body)
    }

    /// Decodes CaptureChange (field 8).
    public static func decodeCaptureChange(_ data: Data) -> (captureType: UInt64, captureID: UInt64, description: String)? {
        guard let fields = try? UUWire.decode(data) else { return nil }
        var captureType: UInt64 = 0
        var captureID: UInt64 = 0
        var desc = ""
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .varint(v)): captureType = v
            case (2, let .varint(v)): captureID = v
            case (3, let .bytes(b)): desc = String(data: b, encoding: .utf8) ?? ""
            default: break
            }
        }
        return (captureType, captureID, desc)
    }

    /// Decodes SystemStateChange (field 15): lock state and cursor shape.
    /// The cursor's x and y are its hotspot in the shape's pixels, not a
    /// place on the screen: the driver places it where the pointer is.
    public static func decodeSystemStateChange(_ data: Data) -> (isLocked: Bool?, cursor: RemoteCursorInfo?)? {
        guard let fields = try? UUWire.decode(data) else { return nil }
        var isLocked: Bool?
        var cursor: RemoteCursorInfo?
        for field in fields {
            switch field.number {
            case 1:
                if case let .varint(v) = field.value { isLocked = v != 0 }
            case 2:
                guard case let .bytes(b) = field.value,
                      let sub = try? UUWire.decode(b) else { continue }
                var x = 0.0, y = 0.0, w = 0, h = 0
                var cursorType = 0
                var xScale = 1.0, yScale = 1.0
                var image: CGImage?
                var visible = false
                for item in sub {
                    switch (item.number, item.value) {
                    case (1, let .varint(v)): x = Double(v.int32Value)
                    case (2, let .varint(v)): y = Double(v.int32Value)
                    case (3, let .varint(v)): w = v.int32Value
                    case (4, let .varint(v)): h = v.int32Value
                    case (5, let .bytes(b)):
                        image = Self.rgbaToCGImage(b, width: w, height: h)
                    case (6, let .varint(v)): cursorType = v.int32Value
                    case (7, let .fixed64(b)):
                        if b.count == 8 { xScale = b.withUnsafeBytes { $0.load(as: Double.self) } }
                    case (8, let .fixed64(b)):
                        if b.count == 8 { yScale = b.withUnsafeBytes { $0.load(as: Double.self) } }
                    case (9, let .varint(v)): visible = v != 0
                    default: break
                    }
                }
                cursor = RemoteCursorInfo(x: x, y: y, width: w, height: h, image: image, visible: visible)
            default: break
            }
        }
        return (isLocked, cursor)
    }

    /// Converts raw RGBA bytes into a CGImage for cursor rendering.
    static func rgbaToCGImage(_ rgba: Data, width: Int, height: Int) -> CGImage? {
        // a cursor is small; the bound also keeps width * height * 4 from overflowing
        guard (1 ... 4096).contains(width), (1 ... 4096).contains(height),
              rgba.count >= width * height * 4 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: rgba as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return image
    }
}
