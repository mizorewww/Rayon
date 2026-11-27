//
//  TerminalContext.swift
//  RayonModule
//
//  Shared SSH terminal session context, previously duplicated between the
//  macOS and iOS apps. The renderer stays in the apps and is injected as a
//  TerminalSessionSurface; interface presentation goes through
//  TerminalInterface.
//

import Foundation
import NIOCore
import os
import RayonSSH
import SwiftUI
import Logger

/// The terminal renderer a session drives, implemented in the apps over
/// RayonTerminalView so RayonModule never links the renderer.
/// `write` takes output from any thread; the callbacks run on the main actor.
public protocol TerminalSessionSurface: AnyObject, Sendable {
    func write(_ string: String)
    func setupBellChain(_ callback: @escaping @MainActor () -> Void)
    func setupBufferChain(_ callback: @escaping @MainActor (String) -> Void)
    func setupTitleChain(_ callback: @escaping @MainActor (String) -> Void)
    func setupSizeChain(_ callback: @escaping @MainActor (CGSize) -> Void)
}

/// The session's state lives on the main actor, like the interface showing
/// it; the shell's input and output stream past it on their own.
@MainActor
open class TerminalContext: ObservableObject, Identifiable, Equatable {
    public nonisolated let id = UUID()

    public var navigationTitle: String {
        switch remoteType {
        case .machine: return machine.shortDescription(withComment: false)
        case .command: return command?.command ?? String(localized: "Unknown Command", bundle: .module)
        case .local: return String(localized: "Local Terminal", bundle: .module)
        }
    }

    public var firstConnect = true
    @Published public var destroyedSession = false {
        didSet {
            if destroyedSession {
                endSSH()
            }
        }
    }

    @Published public var navigationSubtitle: String = ""

    private var title: String {
        didSet { navigationSubtitle = title }
    }

    public enum RemoteType: Sendable {
        case machine
        case command
        case local
    }

    public let remoteType: RemoteType

    public let machine: RDMachine
    public let command: SSHCommandReader?

    /// The SSH shell while one runs: what typing and resizing reach.
    /// Local and UU Remote terminals never have one.
    struct SSHState {
        var shell: SSHShell?
        var input: AsyncStream<ByteBuffer>.Continuation?
        var task: Task<Void, Never>?
    }

    var ssh = SSHState()

    /// On a UU Remote device: the host's session this tab shows.
    public var uuSessionID: UInt32?

    /// The renderer this session writes output to and takes input from.
    public nonisolated let surface: TerminalSessionSurface

    // MARK: - SHELL CONTEXT

    public var closed: Bool { !continueDecision }

    @Published public var interfaceToken: UUID = .init()
    @Published public var interfaceDisabled: Bool = false

    public nonisolated static let defaultTerminalSize = CGSize(width: 80, height: 40)

    /// Wakes a local or UU Remote terminal's loop: on typing, a resize and
    /// closing the tab. Finishing it ends the loop.
    var wake: AsyncStream<Void>.Continuation?
    /// The UU terminal behind this tab, when it is one.
    var uuTerminalLink: UUTerminalLink?

    public var terminalSize: CGSize = defaultTerminalSize {
        didSet {
            if let shell = ssh.shell {
                let size = Self.usableSize(terminalSize)
                shell.resize(columns: Int(size.width), rows: Int(size.height))
            }
            wake?.yield()
        }
    }

    /// A stream for `wake` that keeps one wake-up at most: each look
    /// handles everything that piled up before it.
    func makeWakeStream() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation) {
        let (wakes, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.wake = wake
        return (wakes, wake)
    }

    /// A size too small to be real is the renderer not laid out yet.
    nonisolated static func usableSize(_ size: CGSize) -> CGSize {
        size.width < 8 || size.height < 8 ? defaultTerminalSize : size
    }

    private var dataBuffer: String = ""

    public func getBuffer() -> String {
        defer { dataBuffer = "" }
        return dataBuffer
    }

    public func insertBuffer(_ str: String) {
        guard !closed else { return }
        if let input = ssh.input {
            input.yield(ByteBuffer(string: str))
            return
        }
        dataBuffer += str
        wake?.yield()
    }

    public var continueDecision: Bool = true {
        didSet {
            wake?.yield()
            interfaceDisabled = !continueDecision
        }
    }

    // MARK: SHELL CONTEXT -

    public init(machine: RDMachine, surface: TerminalSessionSurface, resuming uuSession: UInt32? = nil) {
        self.machine = machine
        command = nil
        remoteType = .machine
        title = machine.name
        uuSessionID = uuSession
        self.surface = surface
        // After init returns, as the subclass sets the renderer up first.
        Task { self.processBootstrap() }
    }

    public init(command: SSHCommandReader, surface: TerminalSessionSurface) {
        machine = command.machine
        self.command = command
        title = command.command
        remoteType = .command
        self.surface = surface
        Task { self.processBootstrap() }
    }

    public init(localShell surface: TerminalSessionSurface) {
        machine = RDMachine(name: String(localized: "Local Terminal", bundle: .module))
        command = nil
        title = String(localized: "Local Terminal", bundle: .module)
        remoteType = .local
        self.surface = surface
        Task { self.processBootstrap() }
    }

    public nonisolated static func == (lhs: TerminalContext, rhs: TerminalContext) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func putInformation(_ str: String) {
        if str.isEmpty {
            surface.write("\r\n")
        } else {
            surface.write("\r\n" + str + "\r\n")
        }
    }

    public func processBootstrap() {
        if firstConnect {
            firstConnect = false
            if AppSettings.showsSessionOnConnect.value {
                TerminalInterface.uiHandler.autoOpenInterface(self)
            }
        }

        discardPendingInput()

        Logger.terminal.infoFile("terminal \(id) opening for \(machine.id)")
        if remoteType != .local {
            putInformation("[*] \(String(localized: "Creating Connection", bundle: .module))")
        }
        continueDecision = true

        surface.setupBufferChain { [weak self] buffer in
            self?.insertBuffer(buffer)
        }
        surface.setupTitleChain { [weak self] str in
            self?.title = str
        }
        surface.setupSizeChain { [weak self] size in
            self?.terminalSize = size
        }

        let task = Task { [self] in
            if remoteType == .local {
                #if os(macOS)
                    await runLocalTerminal()
                #else
                    putInformation("[!] \(String(localized: "Local shell is only supported on macOS.", bundle: .module))")
                #endif
            } else if machine.isUURemoteDevice {
                await runUURemoteTerminal()
            } else {
                await runSSHTerminal()
            }
            processShutdown(exitFromShell: true)
        }
        ssh.task = task
    }

    private func runSSHTerminal() async {
        let lease: SSHLease
        do {
            lease = try await SSHConnectionPool.shared.lease(for: machine) { [weak self] hint in
                self?.putInformation(hint)
            }
        } catch {
            putInformation(error.localizedDescription.replacingOccurrences(of: "\n", with: "\r\n"))
            return
        }
        defer { lease.release() }
        guard continueDecision else { return }
        let connection = lease.connection

        if remoteType == .machine {
            let id = machine.id
            let banner = connection.serverVersion.isEmpty ? String(localized: "No Banner", bundle: .module) : connection.serverVersion
            Task { @MainActor in
                RayonStore.shared.updateMachine(id) { $0.lastBanner = banner }
            }
        }

        let terminalType = await prepareTerminalType(on: connection)
        let size = Self.usableSize(terminalSize)
        let shell: SSHShell
        do {
            shell = try await connection.openShell(terminalType: terminalType, columns: Int(size.width), rows: Int(size.height))
        } catch {
            putInformation("[!] " + error.localizedDescription)
            return
        }
        let (input, continuation) = AsyncStream<ByteBuffer>.makeStream()
        ssh.shell = shell
        ssh.input = continuation
        if !dataBuffer.isEmpty { continuation.yield(ByteBuffer(string: dataBuffer)) }
        dataBuffer = ""
        // The renderer's size may have changed while the shell opened.
        let current = Self.usableSize(terminalSize)
        if current != size { shell.resize(columns: Int(current.width), rows: Int(current.height)) }
        do {
            // The renderer takes output from any thread (Ghostty queues it).
            // A character split across two reads waits for its other half.
            let pending = OSAllocatedUnfairLock(initialState: [UInt8]())
            _ = try await shell.run(input: input) { [weak self] chunk in
                let text = pending.withLock { carried in
                    carried.append(contentsOf: chunk.readableBytesView)
                    let complete = Self.completeUTF8Prefix(carried)
                    defer { carried.removeFirst(complete) }
                    return String(decoding: carried[..<complete], as: UTF8.self)
                }
                if !text.isEmpty { self?.surface.write(text) }
            }
        } catch {
            if continueDecision {
                putInformation("[!] " + Self.shellEndedMessage(error, linkActive: connection.isActive, address: machine.remoteAddress))
            }
        }
        ssh.shell = nil
        ssh.input = nil
        Logger.terminal.infoFile("terminal \(id) for \(machine.id) ended")
    }

    /// Why the shell ended, worded for the person. A dropped connection
    /// fails the shell with swift-nio-ssh's error, whose description is
    /// only "NIOSSHError error 1", and the link may not read as closed yet.
    nonisolated static func shellEndedMessage(_ error: Error, linkActive: Bool, address: String) -> String {
        linkActive
            ? String(localized: "The shell ended (\(SSHTransport.describe(error))).", bundle: .module)
            : String(localized: "The connection to \(address) was lost.", bundle: .module)
    }

    /// How many leading bytes end on a whole UTF-8 character.
    nonisolated static func completeUTF8Prefix(_ bytes: [UInt8]) -> Int {
        var index = bytes.count
        // Step back over at most three continuation bytes to a lead byte.
        while index > 0, bytes.count - index < 4, bytes[index - 1] & 0xC0 == 0x80 {
            index -= 1
        }
        guard index > 0 else { return bytes.count }
        let lead = bytes[index - 1]
        let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        return bytes.count - (index - 1) < length ? index - 1 : bytes.count
    }

    /// Ends the SSH shell, if there is one, from this side.
    func endSSH() {
        let state = ssh
        ssh = SSHState()
        state.input?.finish()
        state.shell?.close()
        state.task?.cancel()
    }

    nonisolated static let modeReset = [
        "\u{1B}[=0;1u",
        // Leaving the alternate screen restores the cursor saved on entering
        // it, and on the main screen Ghostty restores whatever was saved last
        // (the top left when nothing was): what follows then overprints the
        // old output. Saving the cursor first makes that restore a no-op on
        // the main screen; on the alternate one it saves the alternate
        // screen's own slot, and the main screen's still comes back.
        "\u{1B}7\u{1B}[?1049l",
        "\u{1B}[=0;1u",
        "\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l",
        "\u{1B}[?1004l\u{1B}[?2004l\u{1B}[?2026l",
        "\u{1B}[>4;0m",
        "\u{1B}[?1l\u{1B}>",
        "\u{1B}[?25h\u{1B}[0m",
    ].joined()

    func discardPendingInput() {
        dataBuffer = ""
    }

    public func processShutdown(exitFromShell: Bool = false) {
        surface.write(Self.modeReset)
        discardPendingInput()
        if exitFromShell {
            putInformation("")
            putInformation("[*] \(String(localized: "Connection Closed", bundle: .module))")
        }
        continueDecision = false
        endSSH()
    }
}
