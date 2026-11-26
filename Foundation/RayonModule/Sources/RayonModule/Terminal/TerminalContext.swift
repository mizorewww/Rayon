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

/// The terminal renderer a session drives, implemented in the apps over
/// RayonTerminalView so RayonModule never links the renderer.
public protocol TerminalSessionSurface: AnyObject {
    func write(_ string: String)
    func setupBellChain(_ callback: @escaping () -> Void)
    func setupBufferChain(_ callback: @escaping (String) -> Void)
    func setupTitleChain(_ callback: @escaping (String) -> Void)
    func setupSizeChain(_ callback: @escaping (CGSize) -> Void)
}

open class TerminalContext: ObservableObject, Identifiable, Equatable, @unchecked Sendable {
    public var id: UUID = .init()

    public var navigationTitle: String {
        switch remoteType {
        case .machine: return machine.shortDescription(withComment: false)
        case .command: return command?.command ?? "Unknown Command"
        case .local: return "Local Terminal"
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

    private var _title: String = ""
    private var title: String {
        get {
            stateAccessLock.lock()
            defer { stateAccessLock.unlock() }
            return _title
        }
        set {
            stateAccessLock.lock()
            _title = newValue
            stateAccessLock.unlock()
            onMainThread { [weak self] in
                self?.navigationSubtitle = newValue
            }
        }
    }

    public enum RemoteType {
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

    let ssh = OSAllocatedUnfairLock(initialState: SSHState())

    /// On a UU Remote device: the host's session this tab shows.
    public var uuSessionID: UInt32?

    /// The renderer this session writes output to and takes input from.
    public let surface: TerminalSessionSurface

    // MARK: - SHELL CONTEXT

    public var closed: Bool { !continueDecision }

    @Published public var interfaceToken: UUID = .init()
    @Published public var interfaceDisabled: Bool = false

    public static let defaultTerminalSize = CGSize(width: 80, height: 40)

    private let stateAccessLock = NSLock()
    private var _terminalSize: CGSize = defaultTerminalSize
    private var _continueDecision: Bool = true
    internal let uuWakeSemaphore = DispatchSemaphore(value: 0)

    public var terminalSize: CGSize {
        get {
            stateAccessLock.lock()
            defer { stateAccessLock.unlock() }
            return _terminalSize
        }
        set {
            stateAccessLock.lock()
            _terminalSize = newValue
            stateAccessLock.unlock()
            if let shell = ssh.withLock({ $0.shell }) {
                let size = Self.usableSize(newValue)
                shell.resize(columns: Int(size.width), rows: Int(size.height))
            }
            uuWakeSemaphore.signal()
        }
    }

    /// A size too small to be real is the renderer not laid out yet.
    static func usableSize(_ size: CGSize) -> CGSize {
        size.width < 8 || size.height < 8 ? defaultTerminalSize : size
    }

    private var _dataBuffer: String = ""
    private var bufferAccessLock = NSLock()

    public func getBuffer() -> String {
        bufferAccessLock.lock()
        defer { bufferAccessLock.unlock() }
        let copy = _dataBuffer
        _dataBuffer = ""
        return copy
    }

    public func insertBuffer(_ str: String) {
        bufferAccessLock.lock()
        guard !closed else {
            bufferAccessLock.unlock()
            return
        }
        if let input = ssh.withLock({ $0.input }) {
            bufferAccessLock.unlock()
            input.yield(ByteBuffer(string: str))
            return
        }
        _dataBuffer += str
        bufferAccessLock.unlock()
        uuWakeSemaphore.signal()
    }

    public var continueDecision: Bool {
        get {
            stateAccessLock.lock()
            defer { stateAccessLock.unlock() }
            return _continueDecision
        }
        set {
            stateAccessLock.lock()
            _continueDecision = newValue
            stateAccessLock.unlock()
            uuWakeSemaphore.signal()
            onMainThread { [weak self] in
                guard let self else { return }
                self.interfaceDisabled = !newValue
            }
        }
    }

    // MARK: SHELL CONTEXT -

    private static let queue = DispatchQueue(
        label: "me.mizorewww.terminal",
        attributes: .concurrent
    )

    public init(machine: RDMachine, surface: TerminalSessionSurface, resuming uuSession: UInt32? = nil) {
        self.machine = machine
        command = nil
        remoteType = .machine
        _title = machine.name
        uuSessionID = uuSession
        self.surface = surface
        Self.queue.async {
            self.processBootstrap()
        }
    }

    public init(command: SSHCommandReader, surface: TerminalSessionSurface) {
        machine = command.machine
        self.command = command
        _title = command.command
        remoteType = .command
        self.surface = surface
        Self.queue.async {
            self.processBootstrap()
        }
    }

    public init(localShell surface: TerminalSessionSurface) {
        machine = RDMachine(name: "Local Terminal")
        command = nil
        _title = "Local Terminal"
        remoteType = .local
        self.surface = surface
        Self.queue.async {
            self.processBootstrap()
        }
    }

    public static func == (lhs: TerminalContext, rhs: TerminalContext) -> Bool {
        lhs.id == rhs.id
    }

    public func putInformation(_ str: String) {
        if str.isEmpty {
            surface.write("\r\n")
        } else {
            surface.write("\r\n" + str + "\r\n")
        }
    }

    public func processBootstrap() {
        onMainThread {
            guard self.firstConnect else { return }
            self.firstConnect = false
            guard MainActor.assumeIsolated({ RayonStore.shared.openInterfaceAutomatically }) else { return }
            TerminalInterface.uiHandler.autoOpenInterface(self)
        }

        discardPendingInput()

        debugPrint("\(self) \(#function) \(machine.id)")
        if remoteType != .local {
            putInformation("[*] Creating Connection")
        }
        continueDecision = true

        surface.setupBellChain {
            debugPrint("terminal bell")
        }
        surface.setupBufferChain { [weak self] buffer in
            self?.insertBuffer(buffer)
        }
        surface.setupTitleChain { [weak self] str in
            self?.title = str
        }
        surface.setupSizeChain { [weak self] size in
            self?.terminalSize = size
        }

        if remoteType == .local {
            #if os(macOS)
                runLocalTerminal()
            #else
                putInformation("[!] Local shell is only supported on macOS.")
            #endif
            onMainThread { self.processShutdown(exitFromShell: true) }
            return
        }

        if machine.isUURemoteDevice {
            runUURemoteTerminal()
            onMainThread { self.processShutdown(exitFromShell: true) }
            return
        }

        let task = Task.detached { [self] in
            await runSSHTerminal()
            onMainThread { self.processShutdown(exitFromShell: true) }
        }
        ssh.withLock { $0.task = task }
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
            let banner = connection.serverVersion.isEmpty ? "No Banner" : connection.serverVersion
            Task { @MainActor in
                guard var read = RayonStore.shared.machine(id), read.lastBanner != banner else { return }
                read.lastBanner = banner
                RayonStore.shared.save(read)
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
        bufferAccessLock.withLock {
            ssh.withLock { $0.shell = shell; $0.input = continuation }
            if !_dataBuffer.isEmpty { continuation.yield(ByteBuffer(string: _dataBuffer)) }
            _dataBuffer = ""
        }
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
            if continueDecision { putInformation("[!] " + error.localizedDescription) }
        }
        ssh.withLock { $0.shell = nil; $0.input = nil }
        debugPrint("\(self) \(#function) ended \(machine.id)")
    }

    /// How many leading bytes end on a whole UTF-8 character.
    static func completeUTF8Prefix(_ bytes: [UInt8]) -> Int {
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
        let state = ssh.withLock { state in
            defer { state = SSHState() }
            return state
        }
        state.input?.finish()
        state.shell?.close()
        state.task?.cancel()
    }

    static let modeReset = [
        "\u{1B}[=0;1u",
        "\u{1B}[?1049l",
        "\u{1B}[=0;1u",
        "\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l",
        "\u{1B}[?1004l\u{1B}[?2004l\u{1B}[?2026l",
        "\u{1B}[>4;0m",
        "\u{1B}[?1l\u{1B}>",
        "\u{1B}[?25h\u{1B}[0m",
    ].joined()

    func discardPendingInput() {
        bufferAccessLock.lock()
        _dataBuffer = ""
        bufferAccessLock.unlock()
    }

    public func processShutdown(exitFromShell: Bool = false) {
        surface.write(Self.modeReset)
        discardPendingInput()
        if exitFromShell {
            putInformation("")
            putInformation("[*] Connection Closed")
        }
        continueDecision = false
        endSSH()
    }
}
