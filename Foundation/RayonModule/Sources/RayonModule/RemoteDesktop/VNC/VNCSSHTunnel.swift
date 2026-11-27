//
//  VNCSSHTunnel.swift
//  RayonModule
//
//  `vncOverSSH`: a direct-tcpip channel — what `ssh -L` opens per
//  connection — to the VNC port on the server's loopback, on the server's
//  pooled SSH connection. There is no local listening port at all: nothing
//  to race for, and no other local process can dial into the tunnel.
//

import Foundation
import NIOCore
import os
import RayonSSH

final class VNCSSHTunnel: Sendable {
    private let machine: RDMachine
    private let targetPort: UInt16
    private let opening = OSAllocatedUnfairLock<Task<VNCTransport, Error>?>(initialState: nil)

    init(machine: RDMachine, targetPort: UInt16) {
        self.machine = machine
        self.targetPort = targetPort
    }

    /// Leases the server's connection and opens the channel to the VNC port.
    func open() async throws -> VNCTransport {
        let machine = machine
        let port = Int(targetPort)
        let task = Task { () throws -> VNCTransport in
            let lease: SSHLease
            do {
                lease = try await SSHConnectionPool.shared.lease(for: machine)
            } catch {
                throw RemoteDesktopFailure(error.localizedDescription)
            }
            try Task.checkCancellation()
            do {
                let stream = try await lease.connection.openByteStream(host: "127.0.0.1", port: port)
                return SSHChannelTransport(stream: stream, lease: lease)
            } catch {
                lease.release()
                throw RemoteDesktopFailure(String(localized: "The SSH server would not forward to VNC port \(port) (\(error.localizedDescription)).", bundle: .module))
            }
        }
        opening.withLock { $0 = task }
        return try await task.value
    }

    /// Stops an `open` that is still under way; an opened transport is
    /// closed by its client.
    func stop() {
        opening.withLock { $0 }?.cancel()
    }
}

/// The VNC client's transport over the channel, holding the connection's
/// lease while it is open.
final class SSHChannelTransport: VNCTransport {
    private let stream: SSHByteStream
    private let lease: SSHLease

    init(stream: SSHByteStream, lease: SSHLease) {
        self.stream = stream
        self.lease = lease
    }

    deinit {
        stream.close()
    }

    func receive(maximumLength: Int) async throws -> Data {
        do {
            return try await Data(stream.receive(maximumLength: maximumLength).readableBytesView)
        } catch SSHError.disconnected {
            throw VNCStreamError.endOfStream
        }
    }

    func send(_ data: Data) {
        stream.send(ByteBuffer(bytes: data))
    }

    func close() {
        stream.close()
        lease.release()
    }
}
