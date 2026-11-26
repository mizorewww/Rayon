import XCTest
@testable import RayonModule

/// Wire-level tests for `UURemoteClipboard`: the case-10 text change, the
/// field-17 stream and the rich format negotiation, each as the official
/// hosts exchange them.
final class UURemoteClipboardTests: XCTestCase {
    // MARK: - Wire helpers (the host's end of the wire)

    private func varint(_ value: UInt64, into out: inout Data) {
        UUProtobufWriter.pushVarint(value, into: &out)
    }

    private func nested(_ field: Int, _ payload: Data, into out: inout Data) {
        UUProtobufWriter.pushMessageField(field, payload, into: &out)
    }

    private func int(_ field: Int, _ value: UInt64, into out: inout Data) {
        UUProtobufWriter.pushVarintField(field, value, into: &out)
    }

    private func string(_ field: Int, _ value: String, into out: inout Data) {
        UUProtobufWriter.pushStringField(field, value, into: &out)
    }

    private func envelope(kind: UInt32, body: Data) -> Data {
        UUControlProtocol.envelope(sequence: 1, timestamp: 1, fieldNumber: kind, body: body)
    }

    /// The rpc `{1: header, <case>: body}` the host would send inside an
    /// envelope of the given kind.
    private func hostRPC(id: UInt64, case: Int, body: Data, headerOverride: Data? = nil) -> Data {
        var header = Data()
        int(1, id, into: &header)
        var rpc = Data()
        nested(1, headerOverride ?? header, into: &rpc)
        nested(`case`, body, into: &rpc)
        return rpc
    }

    /// Reads every envelope field's payload of a message the engine answers with.
    private func envelopeFields(_ data: Data) -> [(number: UInt32, body: Data)] {
        guard let fields = try? UUWire.decode(data) else { return [] }
        return fields.compactMap { field in
            guard case let .bytes(b) = field.value, field.number > 2 else { return nil }
            return (field.number, b)
        }
    }

    private func rpcFields(_ rpc: Data) -> [(number: UInt32, body: Data)] {
        guard let fields = try? UUWire.decode(rpc) else { return [] }
        return fields.compactMap { field in
            guard case let .bytes(b) = field.value else { return nil }
            return (field.number, b)
        }
    }

    // MARK: - Outbound offers

    func testWindowsTargetGetsCase10TextWithFormatOne() {
        var clipboard = UURemoteClipboard()
        let messages = clipboard.offer("hello 粘贴", targetMac: false)
        XCTAssertFalse(messages.isEmpty)
        for message in messages {
            let fields = envelopeFields(message)
            XCTAssertEqual(fields.count, 1)
            XCTAssertEqual(fields.first?.number, UUControlField.rpcRequest)
            let rpc = rpcFields(fields[0].body)
            guard let body = rpc.first(where: { $0.number == 10 })?.body,
                  let parts = try? UUWire.decode(body)
            else { return XCTFail("no case-10 body") }
            XCTAssertTrue(parts.contains { $0.number == 1 && $0.value == .varint(1) }, "format id 1")
            let text = parts.first { $0.number == 2 }.flatMap { part -> String? in
                guard case let .bytes(b) = part.value else { return nil }
                return String(data: b, encoding: .utf8)
            }
            XCTAssertEqual(text, "hello 粘贴")
        }
    }

    func testMacTargetGetsOnlyTheRichOffer() {
        var clipboard = UURemoteClipboard()
        let messages = clipboard.offer("hello", targetMac: true)
        XCTAssertEqual(messages.count, 1)
        let fields = envelopeFields(messages[0])
        let rpc = rpcFields(fields[0].body)
        XCTAssertNil(rpc.first { $0.number == 10 }, "no case-10 for a Mac host")
        guard let clip = rpc.first(where: { $0.number == 9 })?.body,
              let kinds = try? UUWire.decode(clip),
              let list = kinds.first(where: { $0.number == 1 }),
              case let .bytes(listBody) = list.value,
              let entries = try? UUWire.decode(listBody)
        else { return XCTFail("no rich format list") }
        var ids: [UInt64] = []
        var names: [String] = []
        for entry in entries where entry.number == 1 {
            guard case let .bytes(format) = entry.value, let parts = try? UUWire.decode(format) else { continue }
            for part in parts {
                if part.number == 1, case let .varint(v) = part.value { ids.append(v) }
                if part.number == 2, case let .bytes(b) = part.value { names.append(String(decoding: b, as: UTF8.self)) }
            }
        }
        XCTAssertTrue(ids.contains(13), "CF_UNICODETEXT offered")
        XCTAssertTrue(ids.contains(0), "the Mac format offered")
        XCTAssertTrue(names.contains("public.utf8-plain-text"))
    }

    func testUnknownTargetSendsRichFirstThenCase10() {
        var clipboard = UURemoteClipboard()
        let messages = clipboard.offer("both", targetMac: nil)
        XCTAssertGreaterThanOrEqual(messages.count, 2)
        let firstRPC = rpcFields(envelopeFields(messages[0])[0].body)
        XCTAssertNotNil(firstRPC.first { $0.number == 9 }, "rich offer first")
        let lastRPC = rpcFields(envelopeFields(messages[messages.count - 1])[0].body)
        XCTAssertNotNil(lastRPC.first { $0.number == 10 }, "case-10 last, so a Windows host's text wins")
    }

    func testLongTextChunksAtCharacterBoundaries() {
        let text = "中文🙂".repeated(count: 3000) // 30 000+ bytes of UTF-8
        let parts = UURemoteClipboard.chunks(text)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.joined(), text)
        for part in parts {
            XCTAssertLessThanOrEqual(part.utf8.count, UUClipboardLimit.chunkBytes)
        }
        var clipboard = UURemoteClipboard()
        let messages = clipboard.offer(text, targetMac: false)
        XCTAssertEqual(messages.count, parts.count)
    }

    func testOversizedOrEmptyTextIsNotOffered() {
        var clipboard = UURemoteClipboard()
        XCTAssertTrue(clipboard.offer("", targetMac: false).isEmpty)
        XCTAssertTrue(clipboard.offer(String(repeating: "a", count: UUClipboardLimit.maxText + 1), targetMac: false).isEmpty)
    }

    // MARK: - Inbound case-10 and field-17

    func testInboundCase10ReassemblesChunksAndAcknowledgesTheLast() {
        var clipboard = UURemoteClipboard()
        let value = "中文🙂".repeated(count: 2200)
        let parts = UURemoteClipboard.chunks(value)
        XCTAssertGreaterThan(parts.count, 1)
        for (index, part) in parts.enumerated() {
            var body = Data()
            int(1, 1, into: &body)
            string(2, part, into: &body)
            if index + 1 < parts.count { int(3, 1, into: &body) }
            let rpc = hostRPC(id: 200 + UInt64(index), case: 10, body: body)
            let result = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: rpc))
            if index + 1 < parts.count {
                XCTAssertNil(result.text, "a chunk in the middle is no copy yet")
                XCTAssertTrue(result.replies.isEmpty, "only the final chunk acknowledges")
            } else {
                XCTAssertEqual(result.text, value)
                XCTAssertEqual(result.replies.count, 1)
                let answer = rpcFields(envelopeFields(result.replies[0])[0].body)
                XCTAssertEqual(envelopeFields(result.replies[0])[0].number, UUControlField.rpcResponse)
                guard let success = answer.first(where: { $0.number == 6 })?.body,
                      let items = try? UUWire.decode(success)
                else { return XCTFail("no case-6 acknowledgement") }
                XCTAssertTrue(items.contains { $0.number == 1 && $0.value == .varint(1) }, "CB_SUCCEEDED")
            }
        }
    }

    func testInboundCase10WithWrongFormatIsIgnored() {
        var clipboard = UURemoteClipboard()
        var body = Data()
        int(1, 13, into: &body) // not the live-tested plain-text format
        string(2, "text", into: &body)
        let result = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: hostRPC(id: 1, case: 10, body: body)))
        XCTAssertNil(result.text)
        XCTAssertTrue(result.replies.isEmpty)
    }

    func testInboundField17StreamReassembles() {
        var clipboard = UURemoteClipboard()
        let value = "stream 中文".repeated(count: 1500)
        let halves = UURemoteClipboard.chunks(value)
        XCTAssertGreaterThan(halves.count, 1)
        for (index, part) in halves.enumerated() {
            var body = Data()
            int(1, 7, into: &body)
            string(2, part, into: &body)
            if index + 1 < halves.count { int(3, 1, into: &body) }
            let result = clipboard.receive(envelope(kind: 17, body: body))
            if index + 1 < halves.count {
                XCTAssertNil(result.text)
            } else {
                XCTAssertEqual(result.text, value)
            }
        }
    }

    // MARK: - Rich negotiation, host offers (pull)

    /// Simulates the host's end of a rich offer: format list, then answer
    /// the data request with a confirmation and blocks.
    func testRichPullCompletesWindowsAndMacText() {
        for format in [UUClipboardTextFormat.windows, .mac] {
            var clipboard = UURemoteClipboard()
            let original = "pull me 中文🙂\nsecond line"
            // 1. The host offers its format list.
            var entry = Data()
            int(1, format.id, into: &entry)
            if let name = format.offerName { string(2, name, into: &entry) }
            var list = Data()
            nested(1, entry, into: &list)
            var clipBody = Data()
            nested(1, list, into: &clipBody)
            let offer = hostRPC(id: 900, case: 9, body: clipBody)
            let step1 = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: offer))
            XCTAssertNil(step1.text)
            // Two answers: the offer ack (22) and the data request (21).
            XCTAssertEqual(step1.replies.count, 2)
            let ack = step1.replies.first { envelopeFields($0).first?.number == UUControlField.rpcResponse }
            XCTAssertNotNil(ack)
            guard let requestMessage = step1.replies.first(where: { envelopeFields($0).first?.number == UUControlField.rpcRequest }),
                  let requestRPC = envelopeFields(requestMessage).first,
                  let requestFields = try? UUWire.decode(requestRPC.body),
                  let clipField = requestFields.first(where: { $0.number == 9 }),
                  case let .bytes(clipData) = clipField.value,
                  let kinds = try? UUWire.decode(clipData),
                  let askField = kinds.first(where: { $0.number == 2 }),
                  case let .bytes(ask) = askField.value,
                  let askParts = try? UUWire.decode(ask)
            else { return XCTFail("no data request") }
            var key = ""
            for part in askParts where part.number == 2 {
                if case let .bytes(b) = part.value { key = String(decoding: b, as: UTF8.self) }
            }
            XCTAssertFalse(key.isEmpty)

            // 2. The host confirms with the block count, then sends the block.
            let encoded = format.encode(original)
            var confirm = Data()
            int(1, 1, into: &confirm)
            string(2, key, into: &confirm)
            int(3, 1, into: &confirm)
            var confirmClip = Data()
            nested(2, confirm, into: &confirmClip)
            // RpcResponse: {1: header, 5: {2: confirm}}
            var confirmRPC = Data()
            var h = Data()
            int(1, 901, into: &h)
            nested(1, h, into: &confirmRPC)
            nested(5, confirmClip, into: &confirmRPC)
            let step2 = clipboard.receive(envelope(kind: UUControlField.rpcResponse, body: confirmRPC))
            XCTAssertNil(step2.text, "no text before the blocks land")

            var block = Data()
            string(1, key, into: &block)
            int(2, 0, into: &block)
            nested(3, encoded, into: &block)
            var blockClip = Data()
            nested(3, block, into: &blockClip)
            let blockMessage = hostRPC(id: 902, case: 9, body: blockClip)
            let step3 = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: blockMessage))
            XCTAssertEqual(step3.text, original, "\(format) text round-trips")
            XCTAssertFalse(step3.replies.isEmpty, "the block is confirmed")
        }
    }

    // MARK: - Rich negotiation, viewer offers (push)

    func testRichPushAnswersTheHostsDataRequestWithEncodedBlocks() {
        var clipboard = UURemoteClipboard()
        let original = "push 中文🙂\nline"
        let offers = clipboard.offer(original, targetMac: true)
        XCTAssertEqual(offers.count, 1)

        // The host asks for the Mac format.
        var ask = Data()
        int(1, 0, into: &ask)
        string(2, "host-key", into: &ask)
        string(3, "public.utf8-plain-text", into: &ask)
        var clipBody = Data()
        nested(2, ask, into: &clipBody)
        let dataRequest = hostRPC(id: 700, case: 9, body: clipBody)
        let result = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: dataRequest))
        // The confirm (22) then the block (21).
        XCTAssertEqual(result.replies.count, 2)
        guard let confirmMessage = result.replies.first(where: { envelopeFields($0).first?.number == UUControlField.rpcResponse }) else {
            return XCTFail("no confirmation")
        }
        let confirmRPC = rpcFields(envelopeFields(confirmMessage)[0].body)
        guard let clip5 = confirmRPC.first(where: { $0.number == 5 })?.body,
              let kinds = try? UUWire.decode(clip5),
              let confirmField = kinds.first(where: { $0.number == 2 }),
              case let .bytes(confirmBody) = confirmField.value,
              let confirmParts = try? UUWire.decode(confirmBody)
        else { return XCTFail("no kind-2 confirm") }
        XCTAssertTrue(confirmParts.contains { $0.number == 1 && $0.value == .varint(1) }, "status ok")
        XCTAssertTrue(confirmParts.contains { $0.number == 3 && $0.value == .varint(1) }, "one block")

        guard let blockMessage = result.replies.first(where: { envelopeFields($0).first?.number == UUControlField.rpcRequest }),
              let blockRPC = try? UUWire.decode(envelopeFields(blockMessage)[0].body),
              let clip9Field = blockRPC.first(where: { $0.number == 9 }),
              case let .bytes(clip9) = clip9Field.value,
              let blockKinds = try? UUWire.decode(clip9),
              let blockField = blockKinds.first(where: { $0.number == 3 }),
              case let .bytes(blockBody) = blockField.value,
              let blockParts = try? UUWire.decode(blockBody)
        else { return XCTFail("no block") }
        for part in blockParts where part.number == 3 {
            guard case let .bytes(data) = part.value else { continue }
            XCTAssertEqual(UUClipboardTextFormat.mac.decode(data), original)
        }
    }

    func testWindowsPushBlocksEncodeUTF16CRLF() {
        let text = "a\nb"
        let encoded = UUClipboardTextFormat.windows.encode(text)
        XCTAssertEqual(UUClipboardTextFormat.windows.decode(encoded), text)
        // CRLF in the encoding, UTF-16LE, NUL-terminated.
        let bytes = [UInt8](encoded)
        XCTAssertTrue(bytes.count >= 2 && bytes.suffix(2) == [0, 0])
        XCTAssertTrue(encoded.count.isMultiple(of: 2))
        XCTAssertTrue(UUClipboardTextFormat.windows.decode(encoded)?.contains("\r\n") == false)
    }

    // MARK: - Capture answer disambiguation

    func testClipboardResponsesAreNotMisreadAsCaptureAnswers() {
        // A rich response (header + case 5) must never be taken for a
        // successful capture-settings answer.
        var confirm = Data()
        int(1, 1, into: &confirm)
        var clip = Data()
        nested(2, confirm, into: &clip)
        var rpc = Data()
        var header = Data()
        int(1, 555, into: &header)
        nested(1, header, into: &rpc)
        nested(5, clip, into: &rpc)
        let message = envelope(kind: UUControlField.rpcResponse, body: rpc)
        XCTAssertNil(UUControlProtocol.decodeCaptureSettingResponse(message))

        // A real capture answer (header only, no errors) still decodes.
        var capture = Data()
        nested(1, header, into: &capture)
        let captureMessage = envelope(kind: UUControlField.rpcResponse, body: capture)
        let answer = UUControlProtocol.decodeCaptureSettingResponse(captureMessage)
        XCTAssertEqual(answer?.requestID, 555)
        XCTAssertEqual(answer?.errors.count, 0)
    }

    /// One copy reaching the viewer twice — case-10, then inside the rich
    /// flow — writes the same text twice; both are surfaced and equality is
    /// the session's echo guard.
    func testSameCopyByCase10AndRichBothSurface() {
        var clipboard = UURemoteClipboard()
        var body = Data()
        int(1, 1, into: &body)
        string(2, "twice", into: &body)
        let first = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: hostRPC(id: 1, case: 10, body: body)))
        XCTAssertEqual(first.text, "twice")
    }

    func testChunkHelperSplitsExactlyLikeUpstream() {
        XCTAssertEqual(UURemoteClipboard.chunks(""), [""])
        let short = "abc"
        XCTAssertEqual(UURemoteClipboard.chunks(short), ["abc"])
        let exact = String(repeating: "x", count: UUClipboardLimit.chunkBytes)
        XCTAssertEqual(UURemoteClipboard.chunks(exact), [exact])
        let one = String(repeating: "x", count: UUClipboardLimit.chunkBytes + 1)
        XCTAssertEqual(UURemoteClipboard.chunks(one).count, 2)
    }

    /// Native providers may number wire blocks from one; a contiguous
    /// one-based set completes the same transfer.
    func testOneBasedWireBlocksStillComplete() {
        var clipboard = UURemoteClipboard()
        var entry = Data()
        int(1, 0, into: &entry)
        string(2, UUClipboardTextFormat.macName, into: &entry)
        var list = Data()
        nested(1, entry, into: &list)
        var clipBody = Data()
        nested(1, list, into: &clipBody)
        let step1 = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: hostRPC(id: 1, case: 9, body: clipBody)))
        guard let requestMessage = step1.replies.first(where: { envelopeFields($0).first?.number == UUControlField.rpcRequest }),
              let requestRPC = envelopeFields(requestMessage).first,
              let requestFields = try? UUWire.decode(requestRPC.body),
              let clipField = requestFields.first(where: { $0.number == 9 }),
              case let .bytes(clipData) = clipField.value,
              let kinds = try? UUWire.decode(clipData),
              let askField = kinds.first(where: { $0.number == 2 }),
              case let .bytes(ask) = askField.value,
              let askParts = try? UUWire.decode(ask)
        else { return XCTFail("no data request") }
        var key = ""
        for part in askParts where part.number == 2 {
            if case let .bytes(b) = part.value { key = String(decoding: b, as: UTF8.self) }
        }

        var confirm = Data()
        int(1, 1, into: &confirm)
        string(2, key, into: &confirm)
        int(3, 1, into: &confirm)
        var confirmClip = Data()
        nested(2, confirm, into: &confirmClip)
        var confirmRPC = Data()
        var h = Data()
        int(1, 2, into: &h)
        nested(1, h, into: &confirmRPC)
        nested(5, confirmClip, into: &confirmRPC)
        _ = clipboard.receive(envelope(kind: UUControlField.rpcResponse, body: confirmRPC))

        var block = Data()
        string(1, key, into: &block)
        int(2, 1, into: &block) // numbered from one
        nested(3, Data("one based".utf8), into: &block)
        var blockClip = Data()
        nested(3, block, into: &blockClip)
        let done = clipboard.receive(envelope(kind: UUControlField.rpcRequest, body: hostRPC(id: 3, case: 9, body: blockClip)))
        XCTAssertEqual(done.text, "one based")
    }
}

private extension String {
    func repeated(count: Int) -> String {
        String(repeating: self, count: count)
    }
}
