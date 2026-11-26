//
//  VNCSSHTunnel.swift
//  RayonModule
//
//  `vncOverSSH`: a direct-tcpip channel — what `ssh -L` opens per
//  connection — to the VNC port on the server's loopback, over its own
//  NSRemoteShell. The channel is bridged to a socketpair, so there is no
//  local listening port at all: nothing to race for, and no other local
//  process can dial into the tunnel.
//

import Foundation
@preconcurrency import NSRemoteShell

final class VNCSSHTunnel: @unchecked Sendable {
    private let machine: RDMachine
    private let targetPort: UInt16
    private let stateLock = NSLock()
    private var shell: NSRemoteShell?
    private var stopped = false

    init(machine: RDMachine, targetPort: UInt16) {
        self.machine = machine
        self.targetPort = targetPort
    }

    /// Opens the SSH session and the channel to the VNC port.
    func open() async throws -> VNCTransport {
        // NSRemoteShell blocks while it connects; keep it off the
        // cooperative pool.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try self.openBlocking() })
            }
        }
    }

    private func openBlocking() throws -> VNCTransport {
        let shell = NSRemoteShell()
        let proceed = stateLock.withLock { () -> Bool in
            guard !stopped else { return false }
            self.shell = shell
            return true
        }
        guard proceed else {
            shell.destroyPermanently()
            throw CancellationError()
        }
        shell.applyConnection(for: machine, timeout: RayonStore.workerTimeoutNumber)
        let result = shell.connectAndAuthenticate(
            identity: RayonStore.workerAssociatedIdentity(for: machine),
            autoIdentities: RayonStore.workerIdentitiesForAutoAuth,
            username: machine.sshUsernameOverride
        )
        guard result == .success else {
            throw RemoteDesktopFailure(result == .connectFailed
                ? (shell.connectFailureReason ?? "Could not connect for the SSH tunnel.")
                : "SSH authentication failed for the tunnel.")
        }
        let fd = shell.openDirectTCPIPSocketPair(toHost: "127.0.0.1", port: NSNumber(value: targetPort))
        guard fd > 0 else {
            throw RemoteDesktopFailure(shell.getLastError()
                ?? "The SSH server would not forward to VNC port \(targetPort).")
        }
        return VNCSocketPairTransport(fd: fd)
    }

    /// Tears the SSH session down, also mid-`open`; the transport then sees
    /// the end of its stream.
    func stop() {
        let shell = stateLock.withLock { () -> NSRemoteShell? in
            guard !stopped else { return nil }
            stopped = true
            return self.shell
        }
        guard let shell else { return }
        DispatchQueue.global().async {
            shell.requestDisconnectAndWait()
            shell.destroyPermanently()
        }
    }
}

/// A transport over the client end of the tunnel's socketpair, on
/// dispatch I/O: reads return as soon as bytes arrive, writes queue in
/// order without blocking. Writes go through their own descriptor (a dup):
/// one-shot dispatch reads and writes sharing a descriptor serialize, so a
/// read pending for the next server message would hold input back.
final class VNCSocketPairTransport: VNCTransport, @unchecked Sendable {
    private let readFD: Int32
    private let writer: DispatchIO

    init(fd: Int32) {
        readFD = fd
        let writeFD = dup(fd)
        writer = DispatchIO(
            type: .stream,
            fileDescriptor: writeFD,
            queue: .global(),
            cleanupHandler: { _ in Darwin.close(writeFD) }
        )
    }

    /// A pending read holds `self`, so the descriptor cannot be closed —
    /// and reused — under it.
    deinit {
        writer.close(flags: .stop)
        Darwin.close(readFD)
    }

    func receive(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchIO.read(fromFileDescriptor: readFD, maxLength: maximumLength, runningHandlerOn: .global()) { [self] data, error in
                withExtendedLifetime(self) {}
                if error != 0 {
                    continuation.resume(throwing: VNCStreamError.failed(String(cString: strerror(error))))
                } else if data.isEmpty {
                    continuation.resume(throwing: VNCStreamError.endOfStream)
                } else {
                    continuation.resume(returning: Data(data))
                }
            }
        }
    }

    func send(_ data: Data) {
        let chunk = data.withUnsafeBytes { DispatchData(bytes: $0) }
        writer.write(offset: 0, data: chunk, queue: .global()) { [weak self] done, _, error in
            if done, error != 0 { self?.close() }
        }
    }

    func close() {
        // Shutting the socket down wakes a pending read with end-of-stream;
        // the descriptors themselves are closed in deinit.
        shutdown(readFD, SHUT_RDWR)
        writer.close(flags: .stop)
    }
}
