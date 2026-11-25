//
//  UURemoteClipboard.swift
//  CatusshModule
//
//  The UU Remote clipboard engine: the wire formats a host and a viewer
//  exchange on TEXT_DATA_CHANNEL, and the session state machine that turns
//  them into text. Mirrors /tmp/uu-refs/uu-remote-linux/src/clipboard_protocol.rs,
//  src/clipboard_rich.rs and src/viewer/clipboard.rs.
//
//  Three wire forms carry text, and a host may use any of them:
//
//  - Envelope field 17 `ClipboardChange {1: id, 2: text, 3: more}`: the plain
//    stream, chunked. The older form, still pushed to mobile viewers.
//  - Envelope field 21 RpcRequest case 10 `ClipboardTextChangeRequest`
//    `{1: format 1, 2: text, 3: more}`: what the official Windows host
//    applies when it arrives, and what mobile viewers send.
//  - Envelope field 21/22 rich format negotiation (RpcRequest case 9,
//    RpcResponse case 5): the only form the official Mac host exchanges.
//    The offerer lists formats (kind 1), the taker asks for one (kind 2),
//    the offerer answers with a confirmation and data blocks (kind 3).
//

import Foundation

/// Text formats the rich negotiation carries. Windows hosts offer and ask
/// for CF_UNICODETEXT (id 13, UTF-16LE with CRLF line endings); the official
/// Mac host offers its pasteboard as format id 0 named `public.utf8-plain-text`.
public enum UUClipboardTextFormat: Equatable, Sendable {
    case windows
    case mac

    /// Reads a format entry `{1: id, 2/3: name}`; nil when it is no text.
    init?(decoding data: Data) {
        guard let fields = try? UUWire.decode(data) else { return nil }
        var id: UInt64 = 0
        var names: [String] = []
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .varint(v)): id = v
            case (2, let .bytes(b)), (3, let .bytes(b)):
                if let name = String(data: b, encoding: .utf8) { names.append(name) }
            default: break
            }
        }
        if id == UUClipboardTextFormat.windowsID { self = .windows; return }
        if names.contains(UUClipboardTextFormat.macName) { self = .mac; return }
        // The Mac host's format id is 0; take it when the name is missing too.
        if id == 0 { self = .mac; return }
        return nil
    }

    public static let windowsID: UInt64 = 13
    public static let macName = "public.utf8-plain-text"

    var id: UInt64 {
        switch self {
        case .windows: UUClipboardTextFormat.windowsID
        case .mac: 0
        }
    }

    var requestName: String {
        switch self {
        case .windows: "CF_UNICODETEXT"
        case .mac: UUClipboardTextFormat.macName
        }
    }

    /// The offer carries no name for the predefined Windows id: Windows
    /// registers even a predefined format as custom when one is given.
    var offerName: String? {
        switch self {
        case .windows: nil
        case .mac: UUClipboardTextFormat.macName
        }
    }

    func encode(_ text: String) -> Data {
        switch self {
        case .windows:
            let crlf = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
            var data = Data()
            for unit in crlf.utf16 {
                data.append(UInt8(unit & 0xFF))
                data.append(UInt8(unit >> 8))
            }
            data.append(contentsOf: [0, 0])
            return data
        case .mac:
            return Data(text.utf8)
        }
    }

    func decode(_ data: Data) -> String? {
        switch self {
        case .windows:
            guard data.count.isMultiple(of: 2) else { return nil }
            var units: [UInt16] = []
            for index in stride(from: 0, to: data.count, by: 2) {
                units.append(UInt16(data[index]) | UInt16(data[index + 1]) << 8)
            }
            if units.last == 0 { units.removeLast() }
            guard !units.contains(0) else { return nil }
            return String(decoding: units, as: UTF16.self).replacingOccurrences(of: "\r\n", with: "\n")
        case .mac:
            var bytes = data
            if bytes.last == 0 { bytes.removeLast() }
            guard let text = String(data: bytes, encoding: .utf8), !text.contains("\0") else { return nil }
            return text
        }
    }
}

/// One clipboard text in flight to or from a host, capped like upstream.
public enum UUClipboardLimit {
    public static let maxText = 30 * 1024
    /// Case-10/17 chunks sized so worst-case UTF-16 plus framing stays below
    /// the data channel reader's 65535 bytes.
    public static let chunkBytes = 8192
    /// Rich transfer blocks.
    public static let blockBytes = 0x20000
    public static let maxBytes = maxText * 2 + 2
}

/// The case-10/17 chunk reassembly: a text bigger than one chunk arrives as
/// several messages sharing their id and completes on the one without `more`.
public struct UUClipboardAssembly {
    private var pending: (id: UInt64, text: String, started: Date)?

    public init() {}

    /// Accepts one `{1: id, 2: text, 3: more}` body; returns the complete
    /// text on the final chunk, nil while chunks are missing or the message
    /// carries no complete text.
    public mutating func accept(_ body: Data) -> String? {
        guard body.count <= UUClipboardLimit.maxText + 256,
              let fields = try? UUWire.decode(body)
        else { pending = nil; return nil }
        var id: UInt64 = 0
        var text = ""
        var more = false
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .varint(v)): id = v
            case (2, let .bytes(b)): text = String(decoding: b, as: UTF8.self)
            case (3, let .varint(v)): more = v != 0
            default: break
            }
        }
        let now = Date()
        var combined = ""
        if let pending, pending.id == id, now.timeIntervalSince(pending.started) < 5 {
            combined = pending.text
        }
        guard combined.utf8.count + text.utf8.count <= UUClipboardLimit.maxText else { pending = nil; return nil }
        combined += text
        if more {
            pending = (id, combined, pending?.started ?? now)
            return nil
        }
        pending = nil
        return combined
    }
}

/// The clipboard wire state machine. One per connection; the driver feeds it
/// every TEXT_DATA_CHANNEL message and sends the envelopes it returns.
public struct UURemoteClipboard {
    /// The text last offered to the host, kept so its data request can still
    /// be answered after further copies happened locally.
    public private(set) var offeredText: String?
    /// Request/sequence ids count up from 100 like upstream's.
    private var sequence: UInt64 = 100
    /// Reassembly for the field-17 stream and the case-10 RPCs — separate,
    /// a host may interleave them.
    private var streamAssembly = UUClipboardAssembly()
    private var rpcAssembly = UUClipboardAssembly()
    /// An inbound rich transfer: the key the taker asked with, the format,
    /// the block count the confirmation promised and the blocks so far.
    private var inbound: (key: String, format: UUClipboardTextFormat, count: Int?, blocks: [Int: Data])?

    public init() {}

    private mutating func next() -> UInt64 {
        sequence = sequence &+ 1
        if sequence < 100 { sequence = 100 }
        return sequence
    }

    // MARK: - Encoding helpers

    private static func header(_ id: UInt64) -> Data {
        var header = Data()
        UUProtobufWriter.pushVarintField(1, id, into: &header)
        return header
    }

    /// `{1: header, 9: {<kind>: body}}` — a rich RpcRequest.
    private static func richRequest(id: UInt64, kind: Int, body: Data) -> Data {
        var clip = Data()
        UUProtobufWriter.pushMessageField(kind, body, into: &clip)
        var rpc = Data()
        UUProtobufWriter.pushMessageField(1, header(id), into: &rpc)
        UUProtobufWriter.pushMessageField(9, clip, into: &rpc)
        return rpc
    }

    /// `{1: header, 5: {<kind>: body}}` — a rich RpcResponse.
    private static func richResponse(header: Data, kind: Int, body: Data) -> Data {
        var clip = Data()
        UUProtobufWriter.pushMessageField(kind, body, into: &clip)
        var rpc = Data()
        UUProtobufWriter.pushMessageField(1, header, into: &rpc)
        UUProtobufWriter.pushMessageField(5, clip, into: &rpc)
        return rpc
    }

    /// `{1: header, 10: {1: 1, 2: text, 3: more?}}` — a case-10 text change.
    private static func textChangeRequest(id: UInt64, part: String, more: Bool) -> Data {
        var body = Data()
        UUProtobufWriter.pushVarintField(1, 1, into: &body)
        UUProtobufWriter.pushStringField(2, part, into: &body)
        if more { UUProtobufWriter.pushVarintField(3, 1, into: &body) }
        var rpc = Data()
        UUProtobufWriter.pushMessageField(1, header(id), into: &rpc)
        UUProtobufWriter.pushMessageField(10, body, into: &rpc)
        return rpc
    }

    private static func envelope(sequence: UInt64, kind: UInt32, body: Data) -> Data {
        UUControlProtocol.envelope(
            sequence: sequence,
            timestamp: UInt64(Date().timeIntervalSince1970),
            fieldNumber: kind,
            body: body
        )
    }

    /// Text split at chunk boundaries no larger than the channel's reader,
    /// on character boundaries, like upstream's `chunks`.
    static func chunks(_ text: String) -> [String] {
        guard !text.isEmpty else { return [""] }
        var parts: [String] = []
        var current = ""
        var bytes = 0
        for character in text {
            let width = String(character).utf8.count
            if bytes + width > UUClipboardLimit.chunkBytes, !current.isEmpty {
                parts.append(current)
                current = ""
                bytes = 0
            }
            current.append(character)
            bytes += width
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: - Outbound: a local copy offered to the host

    /// The envelopes carrying a local copy to the host. Two forms exist
    /// because hosts are live-tested to take only theirs: the official
    /// Windows host writes the case-10 text and, if a rich list arrives
    /// after, replaces it with a placeholder it never renders; the official
    /// Mac host only takes the rich offer. Unknown targets get the rich
    /// offer first so the case-10 text lands last and wins.
    public mutating func offer(_ text: String, targetMac: Bool?) -> [Data] {
        guard text.utf8.count <= UUClipboardLimit.maxText, !text.isEmpty, !text.contains("\0") else { return [] }
        offeredText = text
        var messages: [Data] = []
        let richPayload = Self.richOffer(id: next(), formats: [.windows, .mac])
        let rich = Self.envelope(sequence: next(), kind: UUControlField.rpcRequest, body: richPayload)
        let parts = Self.chunks(text)
        let texts = parts.enumerated().map { index, part in
            Self.envelope(
                sequence: next(),
                kind: UUControlField.rpcRequest,
                body: Self.textChangeRequest(id: next(), part: part, more: index + 1 < parts.count)
            )
        }
        switch targetMac {
        case .some(true): messages = [rich]
        case .some(false): messages = texts
        case .none: messages = [rich] + texts
        }
        return messages
    }

    /// The kind-1 format list offer `{1: {1: id, 2: name?} …}` inside a rich
    /// RpcRequest. Both text formats are listed; the host picks its own.
    private static func richOffer(id: UInt64, formats: [UUClipboardTextFormat]) -> Data {
        var list = Data()
        for format in formats {
            var entry = Data()
            UUProtobufWriter.pushVarintField(1, format.id, into: &entry)
            if let name = format.offerName { UUProtobufWriter.pushStringField(2, name, into: &entry) }
            UUProtobufWriter.pushMessageField(1, entry, into: &list)
        }
        return richRequest(id: id, kind: 1, body: list)
    }

    // MARK: - Inbound: messages from the host

    public struct ReceiveResult: Equatable {
        public var replies: [Data] = []
        public var text: String?
        /// The message carried clipboard-shaped content at all (even a bare
        /// acknowledgement, which is nobody else's business either).
        public var handled = false
    }

    /// Takes one TEXT_DATA_CHANNEL message; answers what has to be answered
    /// and surfaces complete clipboard text. Anything not clipboard-shaped
    /// is nobody's business here and returns empty.
    public mutating func receive(_ data: Data) -> ReceiveResult {
        guard data.count <= UUClipboardLimit.maxBytes + 1024,
              let fields = try? UUWire.decode(data)
        else { return ReceiveResult() }
        var result = ReceiveResult()
        for field in fields {
            guard case let .bytes(payload) = field.value else { continue }
            switch field.number {
            case 17:
                result.handled = true
                if let text = streamAssembly.accept(payload) {
                    result.text = text
                }
            case UUControlField.rpcRequest:
                receiveRichRequest(payload, into: &result)
                receiveTextChange(payload, into: &result)
            case UUControlField.rpcResponse:
                receiveRichResponse(payload, into: &result)
                receiveTextAcknowledgement(payload, into: &result)
            default:
                break
            }
        }
        if let text = result.text, text.contains("\0") { result.text = nil }
        return result
    }

    /// Case-10 inbound: reassemble and acknowledge the final chunk with the
    /// case-6 `TextChangeResponse` (`err` 1 = CB_SUCCEEDED) on field 22.
    private mutating func receiveTextChange(_ rpc: Data, into result: inout ReceiveResult) {
        guard let fields = try? UUWire.decode(rpc) else { return }
        var header: Data?
        var body: Data?
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .bytes(b)): header = b
            case (10, let .bytes(b)): body = b
            default: break
            }
        }
        guard let header, let body, header.count <= 32 else { return }
        result.handled = true
        // Only format 1 plain text is live-known to land on either direction.
        guard let parts = try? UUWire.decode(body),
              parts.contains(where: { $0.number == 1 && $0.value == .varint(1) })
        else { return }
        guard let text = rpcAssembly.accept(body) else { return }
        var response = Data()
        UUProtobufWriter.pushMessageField(1, header, into: &response)
        var success = Data()
        UUProtobufWriter.pushVarintField(1, 1, into: &success)
        UUProtobufWriter.pushMessageField(6, success, into: &response)
        result.replies.append(Self.envelope(sequence: next(), kind: UUControlField.rpcResponse, body: response))
        result.text = text
    }

    /// The case-6 acknowledgement to a case-10 push of ours: status only,
    /// but clipboard-shaped, so nobody else should treat the message as text.
    private mutating func receiveTextAcknowledgement(_ rpc: Data, into result: inout ReceiveResult) {
        guard let fields = try? UUWire.decode(rpc) else { return }
        if fields.contains(where: { $0.number == 6 }) { result.handled = true }
    }

    /// Rich RpcRequest inbound (case 9): format list offers, data requests
    /// for a text we offered, and data blocks of a transfer we asked for.
    private mutating func receiveRichRequest(_ rpc: Data, into result: inout ReceiveResult) {
        guard rpc.count <= UUClipboardLimit.maxBytes + 512,
              let fields = try? UUWire.decode(rpc)
        else { return }
        var header: Data?
        var clip: Data?
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .bytes(b)): header = b
            case (9, let .bytes(b)): clip = b
            default: break
            }
        }
        guard let header, let clip, header.count <= 32,
              let kinds = try? UUWire.decode(clip)
        else { return }
        result.handled = true
        for kind in kinds {
            guard case let .bytes(body) = kind.value else { continue }
            switch kind.number {
            case 1: receiveFormatList(header: header, body: body, into: &result)
            case 2: receiveDataRequest(header: header, body: body, into: &result)
            case 3: receiveDataBlock(header: header, body: body, into: &result)
            default: break
            }
        }
    }

    /// A format list offer: acknowledge it (even one without text, so the
    /// host's state machine moves on), then ask for the text when a known
    /// text format is in it. Windows is preferred when both are offered.
    private mutating func receiveFormatList(header: Data, body: Data, into result: inout ReceiveResult) {
        result.replies.append(Self.envelope(
            sequence: next(),
            kind: UUControlField.rpcResponse,
            body: Self.richResponse(header: header, kind: 1, body: Data())
        ))
        guard let fields = try? UUWire.decode(body) else { return }
        var offered: [UUClipboardTextFormat] = []
        for field in fields where field.number == 1 {
            guard case let .bytes(entry) = field.value, let format = UUClipboardTextFormat(decoding: entry) else { continue }
            offered.append(format)
        }
        guard let format = offered.contains(.windows) ? .windows : offered.first else {
            inbound = nil
            return
        }
        let id = next()
        let epoch = UInt32(Date().timeIntervalSince1970)
        let key = String(format: "%08x-0000-4000-8000-%012x", epoch, id & 0xFFFFFFFFFFFF)
        var ask = Data()
        UUProtobufWriter.pushVarintField(1, format.id, into: &ask)
        UUProtobufWriter.pushStringField(2, key, into: &ask)
        UUProtobufWriter.pushStringField(3, format.requestName, into: &ask)
        inbound = (key: key, format: format, count: nil, blocks: [:])
        result.replies.append(Self.envelope(
            sequence: next(),
            kind: UUControlField.rpcRequest,
            body: Self.richRequest(id: id, kind: 2, body: ask)
        ))
    }

    /// The host asks for a text we offered: confirm with the block count,
    /// then send the blocks. A format or key mismatch answers unavailable.
    private mutating func receiveDataRequest(header: Data, body: Data, into result: inout ReceiveResult) {
        guard let fields = try? UUWire.decode(body) else { return }
        var key = ""
        var formatID: UInt64 = 0
        var name = ""
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .varint(v)): formatID = v
            case (2, let .bytes(b)): key = String(decoding: b, as: UTF8.self)
            case (3, let .bytes(b)): name = String(decoding: b, as: UTF8.self)
            default: break
            }
        }
        guard !key.isEmpty, key.count <= 256 else { return }
        let format: UUClipboardTextFormat? = formatID == UUClipboardTextFormat.windowsID ? .windows
            : name == UUClipboardTextFormat.macName ? .mac
            : formatID == 0 ? .mac : nil
        let data = format.flatMap { fmt in offeredText.map { fmt.encode($0) } }
        var confirm = Data()
        UUProtobufWriter.pushVarintField(1, data != nil ? 1 : 2, into: &confirm)
        UUProtobufWriter.pushStringField(2, key, into: &confirm)
        if let data {
            let count = max(1, (data.count + UUClipboardLimit.blockBytes - 1) / UUClipboardLimit.blockBytes)
            UUProtobufWriter.pushVarintField(3, UInt64(count), into: &confirm)
        }
        result.replies.append(Self.envelope(
            sequence: next(),
            kind: UUControlField.rpcResponse,
            body: Self.richResponse(header: header, kind: 2, body: confirm)
        ))
        guard let data else { return }
        let count = max(1, (data.count + UUClipboardLimit.blockBytes - 1) / UUClipboardLimit.blockBytes)
        for index in 0 ..< count {
            let start = index * UUClipboardLimit.blockBytes
            let end = min(start + UUClipboardLimit.blockBytes, data.count)
            var block = Data()
            UUProtobufWriter.pushStringField(1, key, into: &block)
            UUProtobufWriter.pushVarintField(2, UInt64(index), into: &block)
            UUProtobufWriter.pushBytesField(3, data[start ..< end], into: &block)
            result.replies.append(Self.envelope(
                sequence: next(),
                kind: UUControlField.rpcRequest,
                body: Self.richRequest(id: next(), kind: 3, body: block)
            ))
        }
    }

    /// A block of a transfer we asked for: confirm it and complete the text
    /// when every promised block is in.
    private mutating func receiveDataBlock(header: Data, body: Data, into result: inout ReceiveResult) {
        guard let fields = try? UUWire.decode(body) else { return }
        var key = ""
        var index = 0
        var data = Data()
        for field in fields {
            switch (field.number, field.value) {
            case (1, let .bytes(b)): key = String(decoding: b, as: UTF8.self)
            case (2, let .varint(v)): index = v.int32Value
            case (3, let .bytes(b)): data = b
            default: break
            }
        }
        guard index >= 0, index <= UUClipboardLimit.maxBytes / UUClipboardLimit.blockBytes + 1,
              data.count <= UUClipboardLimit.maxBytes,
              inbound?.key == key
        else { return }
        inbound?.blocks[index] = data
        var confirm = Data()
        UUProtobufWriter.pushStringField(1, key, into: &confirm)
        UUProtobufWriter.pushVarintField(2, UInt64(index), into: &confirm)
        UUProtobufWriter.pushVarintField(3, 1, into: &confirm)
        result.replies.append(Self.envelope(
            sequence: next(),
            kind: UUControlField.rpcResponse,
            body: Self.richResponse(header: header, kind: 3, body: confirm)
        ))
        if let text = completeInbound() {
            result.text = text
        }
    }

    /// Rich RpcResponse inbound (case 5): the confirmation to our data
    /// request carries the block count to expect.
    private mutating func receiveRichResponse(_ rpc: Data, into result: inout ReceiveResult) {
        guard let fields = try? UUWire.decode(rpc) else { return }
        if fields.contains(where: { $0.number == 5 }) { result.handled = true }
        for field in fields where field.number == 5 {
            guard case let .bytes(clip) = field.value,
                  let kinds = try? UUWire.decode(clip)
            else { continue }
            for kind in kinds where kind.number == 2 {
                guard case let .bytes(confirm) = kind.value,
                      let parts = try? UUWire.decode(confirm)
                else { continue }
                var status: UInt64 = 0
                var key = ""
                var count: UInt64 = 0
                for part in parts {
                    switch (part.number, part.value) {
                    case (1, let .varint(v)): status = v
                    case (2, let .bytes(b)): key = String(decoding: b, as: UTF8.self)
                    case (3, let .varint(v)): count = v
                    default: break
                    }
                }
                guard status == 1, key == inbound?.key, count > 0,
                      count <= UInt64(UUClipboardLimit.maxBytes / UUClipboardLimit.blockBytes + 2)
                else { continue }
                inbound?.count = Int(count)
                if let text = completeInbound() {
                    result.text = text
                }
            }
        }
    }

    /// The transfer completes when the confirmation's count is in and every
    /// block is here; the concatenation decodes per the format. Native
    /// providers may number wire blocks from one while their internal
    /// slicing is zero-based, so a complete contiguous set is accepted in
    /// either convention — never completed from a missing middle block.
    private mutating func completeInbound() -> String? {
        guard let state = inbound, let count = state.count, count > 0 else { return nil }
        let first: Int
        if (0 ..< count).allSatisfy({ state.blocks[$0] != nil }) {
            first = 0
        } else if (1 ... count).allSatisfy({ state.blocks[$0] != nil }) {
            first = 1
        } else {
            return nil
        }
        var data = Data()
        for index in first ..< first + count {
            data.append(state.blocks[index] ?? Data())
        }
        guard data.count <= UUClipboardLimit.maxBytes else { inbound = nil; return nil }
        inbound = nil
        return state.format.decode(data)
    }
}
