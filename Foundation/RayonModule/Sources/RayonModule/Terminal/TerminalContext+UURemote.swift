//
//  TerminalContext+UURemote.swift
//  RayonModule
//
//  A terminal on a UU Remote device: the host's own shell over the device's
//  UU connection (TERM frames on its binary channel), no SSH. Runs in the
//  session's task like the SSH loop, and ends the same way.
//

import Combine
import Foundation
import Synchronization
import UURemoteKit

extension TerminalContext {
    /// Wakes on typing, a resize, closing the tab, and the link ending or
    /// its connection closing; nothing else needs a look.
    func runUURemoteTerminal() async {
        putInformation("[*] \(String(localized: "Connecting through UU Remote", bundle: .module))")
        let (wakes, wake) = makeWakeStream()
        let link = UUTerminalLink(machine: machine, wake: wake)
        uuTerminalLink = link
        link.connect(context: self, size: terminalSize)

        for await _ in wakes {
            guard !closed else { break }
            link.pump(typed: getBuffer(), size: terminalSize, context: self)
        }

        self.wake = nil
        link.end()
        uuTerminalLink = nil
    }
}

@MainActor
final class UUTerminalLink {
    let machine: RDMachine
    /// Wakes the terminal's loop; finishing it ends the loop.
    let wake: AsyncStream<Void>.Continuation
    private var connection: UURemoteConnection? {
        didSet {
            // A dropped connection wakes the loop, whose pump resumes the session.
            closing = connection?.$isClosed.filter { $0 }.sink { [wake] _ in wake.yield() }
        }
    }
    private var closing: AnyCancellable?
    private var terminalID: UInt32?
    private var sentSize: CGSize = .zero
    private var openedAt = Date.distantFuture
    private var ended = false
    /// When the connection last dropped under a session that was resumed.
    private var resumes: [Date] = []
    private let decoder = UTF8StreamDecoder()

    init(machine: RDMachine, wake: AsyncStream<Void>.Continuation) {
        self.machine = machine
        self.wake = wake
    }

    func connect(context: TerminalContext, size: CGSize) {
        Task { @MainActor [weak self, weak context] in
            guard let self, let context else { return }
            do {
                let connection = try await UURemoteConnections.shared.acquire(self.machine.uuTarget)
                guard !self.ended else {
                    UURemoteConnections.shared.release(connection)
                    return
                }
                self.connection = connection
                self.sentSize = size
                let attaching = context.uuSessionID
                self.openedAt = attaching == nil ? Date() : .distantPast
                let id = connection.openTerminal(
                    sessionID: attaching,
                    cols: Int(max(size.width, 8)), rows: Int(max(size.height, 8))
                ) { [weak self, weak context] frame in
                    guard let self, let context else { return }
                    self.handle(frame, context: context)
                }
                self.terminalID = id
                context.uuSessionID = id
                if attaching != nil {
                    context.putInformation("[*] \(String(localized: "Resumed the session on \(self.machine.name)", bundle: .module))")
                    let cols = Int(max(size.width, 8)), rows = Int(max(size.height, 8))
                    connection.resizeTerminal(cols: cols, rows: max(rows - 1, 8), sessionID: id)
                    connection.resizeTerminal(cols: cols, rows: rows, sessionID: id)
                }
                self.wake.yield()
            } catch {
                context.putInformation("[!] " + error.localizedDescription)
                self.wake.finish()
            }
        }
    }

    private func handle(_ frame: UUTerminalFrame, context: TerminalContext) {
        switch frame.kind {
        case .stdout, .error:
            let text = decoder.decode(frame.payload)
            if !text.isEmpty { context.surface.write(text) }
        case .openResponse:
            if let refusal = frame.openFailure {
                context.putInformation("[!] \(String(localized: "The device refused the terminal: \(refusal.message) (\(refusal.code))", bundle: .module))")
                context.uuSessionID = nil
                wake.finish()
            }
        case .exit:
            let ended = frame.exitCode.map { String(localized: "Shell ended (exit \($0))", bundle: .module) }
                ?? String(localized: "Shell ended", bundle: .module)
            context.putInformation("\r\n[*] \(ended)")
            context.uuSessionID = nil
            wake.finish()
        case .close:
            wake.finish()
        default:
            break
        }
    }

    func pump(typed: String, size: CGSize, context: TerminalContext) {
        guard let connection, let id = terminalID, !ended else { return }
        if connection.isClosed {
            resume(after: connection, size: size, context: context)
            return
        }
        let input = Date().timeIntervalSince(openedAt) < Self.startupReplyWindow ? TerminalReplies.dropping(from: typed) : typed
        if !input.isEmpty { connection.sendTerminalInput(Data(input.utf8), sessionID: id) }
        if size != sentSize, size.width >= 8, size.height >= 8 {
            sentSize = size
            connection.resizeTerminal(cols: Int(size.width), rows: Int(size.height), sessionID: id)
        }
    }

    static let startupReplyWindow: TimeInterval = 3

    /// The connection dropped under the tab. The host keeps the session
    /// through it, so the tab attaches to it again on a new connection, a few
    /// times at most: a device that keeps dropping it ends the tab.
    private func resume(after dropped: UURemoteConnection, size: CGSize, context: TerminalContext) {
        self.connection = nil
        terminalID = nil
        UURemoteConnections.shared.release(dropped)
        let now = Date()
        resumes = resumes.filter { now.timeIntervalSince($0) < Self.resumeWindow }
        // A desktop's connection ends when the desktop is closed, which is
        // no sign of a device that keeps dropping: it does not count, and
        // the desktop only comes back when it is opened again.
        let counts = dropped.purpose != .desktop
        guard context.uuSessionID != nil, !counts || resumes.count < Self.resumeLimit else {
            context.putInformation("\r\n[!] \(String(localized: "The UU Remote connection dropped.", bundle: .module))")
            wake.finish()
            return
        }
        if counts { resumes.append(now) }
        context.putInformation("\r\n[*] \(String(localized: "The UU Remote connection dropped, reconnecting", bundle: .module))")
        Task { @MainActor [weak self, weak context] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, let context, !self.ended else { return }
            self.connect(context: context, size: size)
        }
    }

    static let resumeLimit = 3
    static let resumeWindow: TimeInterval = 300

    func end() {
        guard !ended else { return }
        ended = true
        guard let connection else { return }
        if let id = terminalID, !connection.isClosed { connection.detachTerminal(id) }
        UURemoteConnections.shared.release(connection)
    }
}

/// UTF-8 text out of chunks that may split a character between them.
final class UTF8StreamDecoder: Sendable {
    private let pendingBytes = Mutex(Data())

    func decode(_ chunk: Data) -> String {
        pendingBytes.withLock { Self.decode(chunk, pending: &$0) }
    }

    private static func decode(_ chunk: Data, pending: inout Data) -> String {
        pending.append(chunk)
        guard !pending.isEmpty else { return "" }
        var end = pending.count
        for back in 1 ... min(3, pending.count) {
            let byte = pending[pending.startIndex + pending.count - back]
            if byte & 0xC0 == 0x80 { continue }
            let needed: Int
            switch byte {
            case 0xC2...0xDF: needed = 2
            case 0xE0...0xEF: needed = 3
            case 0xF0...0xF4: needed = 4
            default: needed = 1
            }
            if needed > back { end = pending.count - back }
            break
        }
        let complete = pending.prefix(end)
        if end == pending.count {
            pending.removeAll(keepingCapacity: true)
        } else {
            pending = Data(pending.dropFirst(end))
        }
        return String(decoding: complete, as: UTF8.self)
    }
}

enum TerminalReplies {
    static func dropping(from text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return replyPattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
        )
    }

    private static let replyPattern = try! NSRegularExpression(pattern: [
        "\u{1B}\\[[?>=][0-9;]*c",
        "\u{1B}P>\\|[^\u{1B}]*\u{1B}\\\\",
        "\u{1B}\\][0-9]+;rgb:[^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)",
        "\u{1B}\\[\\?[0-9;]*\\$y",
    ].joined(separator: "|"))
}
