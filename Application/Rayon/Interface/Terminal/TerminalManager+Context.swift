//
//  TerminalManager+Context.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import Foundation
import NSRemoteShell
import RayonModule
import RayonTerminal
import SwiftUI

extension TerminalManager {
    class Context: ObservableObject, Identifiable, Equatable {
        var id: UUID = .init()

        var navigationTitle: String {
            switch remoteType {
            case .machine: return machine.shortDescription(withComment: false)
            case .command: return command?.command ?? "Unknown Command"
            }
        }

        @Published var navigationSubtitle: String = ""

        private var title: String = "" {
            didSet {
                onMainThread {
                    self.navigationSubtitle = self.title
                }
            }
        }

        enum RemoteType {
            case machine
            case command
        }

        let remoteType: RemoteType

        let machine: RDMachine
        let command: SSHCommandReader?
        var shell: NSRemoteShell = .init()

        // MARK: - SHELL CONTEXT

        var closed: Bool { !continueDecision }

        @Published var interfaceToken: UUID = .init()
        @Published var interfaceDisabled: Bool = false

        static let defaultTerminalSize = CGSize(width: 80, height: 40)

        var terminalSize: CGSize = defaultTerminalSize {
            didSet {
                shell.explicitRequestStatusPickup()
            }
        }

        private var _dataBuffer: String = ""
        private var bufferAccessLock = NSLock()

        func getBuffer() -> String {
            bufferAccessLock.lock()
            defer { bufferAccessLock.unlock() }
            let copy = _dataBuffer
            _dataBuffer = ""
            return copy
        }

        func insertBuffer(_ str: String) {
            bufferAccessLock.lock()
            defer { bufferAccessLock.unlock() }
            guard !closed else { return }
            _dataBuffer += str
            Context.queue.async { [weak self] in
                self?.shell.explicitRequestStatusPickup()
            }
        }

        var continueDecision: Bool = true {
            didSet {
                onMainThread {
                    self.interfaceDisabled = !self.continueDecision
                }
            }
        }

        // MARK: SHELL CONTEXT -

        let termInterface: RayonTerminalView = .init()

        private static let queue = DispatchQueue(
            label: "wiki.qaq.terminal",
            attributes: .concurrent
        )

        init(machine: RDMachine) {
            self.machine = machine
            command = nil
            remoteType = .machine
            title = machine.name
            Context.queue.async {
                self.processBootstrap()
            }
        }

        init(command: SSHCommandReader) {
            machine = RDMachine(
                remoteAddress: command.remoteAddress,
                remotePort: command.remotePort,
                name: command.remoteAddress,
                group: "SSHCommandReader",
                associatedIdentity: nil
            )
            self.command = command
            title = command.command
            remoteType = .command
            Context.queue.async {
                self.processBootstrap()
            }
        }

        func setupShellData() {
            shell.applyConnection(for: machine, timeout: RayonStore.shared.timeoutNumber)
        }

        static func == (lhs: Context, rhs: Context) -> Bool {
            lhs.id == rhs.id
        }

        func putInformation(_ str: String) {
            termInterface.write(str + "\r\n")
        }

        func processBootstrap() {
            defer {
                onMainThread { self.processShutdown(exitFromShell: true) }
            }

            setupShellData()

            debugPrint("\(self) \(#function) \(machine.id)")
            putInformation("[*] Creating Connection")
            continueDecision = true

            termInterface
                .setupBellChain {
                    debugPrint("terminal bell")
                }
                .setupBufferChain { [weak self] buffer in
                    self?.insertBuffer(buffer)
                }
                .setupTitleChain { [weak self] str in
                    self?.title = str
                }
                .setupSizeChain { [weak self] size in
                    self?.terminalSize = size
                }

            let identity: RDIdentity?
            if machine.associatedIdentity != nil {
                guard let resolved = RayonStore.shared.associatedIdentity(for: machine) else {
                    putInformation("Malformed machine or identity data")
                    return
                }
                identity = resolved
            } else {
                identity = nil
            }

            let result = shell.connectAndAuthenticate(
                identity: identity,
                autoIdentities: RayonStore.shared.identityGroupForAutoAuth
            ) { [self] hintText in
                putInformation(hintText)
            }
            switch result {
            case .success:
                break
            case .connectFailed:
                putInformation("Unable to connect for \(machine.remoteAddress):\(machine.remotePort)")
                return
            case .authenticateFailed:
                putInformation("Failed to authenticate connection")
                putInformation("Did you forget to add identity or enable auto authentication?")
                return
            }

            onMainThread {
                guard self.remoteType == .machine else {
                    return
                }
                var read = RayonStore.shared.machineGroup[self.machine.id]
                if read.isNotPlaceholder() {
                    read.lastBanner = self.shell.remoteBanner ?? "No Banner"
                    RayonStore.shared.machineGroup[self.machine.id] = read
                }
            }

            shell.begin(withTerminalType: "xterm") {
                debugPrint("channel open")
            } withTerminalSize: { [weak self] in
                var size = self?.terminalSize ?? Context.defaultTerminalSize
                if size.width < 8 || size.height < 8 {
                    // something went wrong
                    size = Context.defaultTerminalSize
                }
                return size
            } withWriteDataBuffer: { [weak self] in
                self?.getBuffer() ?? ""
            } withOutputDataBuffer: { [weak self] output in
                // The main queue is FIFO, so writes stay ordered without
                // blocking the shell IO thread on the UI run loop.
                onMainThread {
                    self?.termInterface.write(output)
                }
            } withContinuationHandler: { [weak self] in
                self?.continueDecision ?? false
            }

            // leave loop
            debugPrint("\(self) \(#function) defer \(machine.id)")

            processShutdown()
        }

        func processShutdown(exitFromShell: Bool = false) {
            if exitFromShell {
                putInformation("")
                putInformation("[*] Connection Closed")
            }
            if let lastError = shell.getLastError() {
                putInformation("[i] Last Error Provided By Backend")
                putInformation("    " + lastError)
            }
            continueDecision = false
            Context.queue.async {
                self.shell.requestDisconnectAndWait()
            }
        }
    }
}
