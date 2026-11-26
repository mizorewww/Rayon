//
//  NSRemoteShell+UURemote.swift
//  RayonModule
//
//  SSH (and SFTP, port forwards) to a UU device: the shell's socket is a
//  UURemoteKit port-mapped stream to the device's own sshd.
//

import Foundation
import NSRemoteShell
import ObjectiveC
import os

private nonisolated(unsafe) let uuTunnelFailureKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

public extension NSRemoteShell {
    /// Why the last connection through UU Remote could not be made, for the
    /// person; nil after one that got through, or one made over TCP.
    var uuTunnelFailure: String? {
        get { objc_getAssociatedObject(self, uuTunnelFailureKey) as? String }
        set { objc_setAssociatedObject(self, uuTunnelFailureKey, newValue, .OBJC_ASSOCIATION_COPY) }
    }

    /// Has the shell reach the machine through UU Remote. The device's
    /// connection is made for the stream if there is none, and kept while
    /// it is open.
    internal func applyUUTransport(for machine: RDMachine) {
        uuTunnelFailure = nil
        setupConnectionSocketProvider { [weak self] host, port, timeout in
            let targetPort = UInt16(port.intValue > 0 ? port.intValue : 22)
            // A UU server's address is its device id, not an IP: the
            // service is on the device's own loopback. Only a dotted address
            // is forwarded as is.
            let targetHost = (host == machine.uuDeviceID || !host.contains(".")) ? "127.0.0.1" : host
            switch Self.openUUStream(to: machine, host: targetHost, port: targetPort, timeout: max(timeout.doubleValue, 15)) {
            case let .success(fd):
                self?.uuTunnelFailure = nil
                return fd
            case let .failure(failure):
                self?.uuTunnelFailure = failure.message
                return -1
            }
        }
    }

    /// The socket provider runs on the shell's own thread and wants a
    /// descriptor back: it waits here for the kit's stream.
    private static func openUUStream(to machine: RDMachine, host: String, port: UInt16, timeout: TimeInterval) -> Result<Int32, UURemoteFailure> {
        guard !Thread.isMainThread else { return .failure(UURemoteFailure("UU Remote streams are not opened on the main thread.")) }
        let done = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock<Result<Int32, UURemoteFailure>>(initialState: .failure(UURemoteFailure("UU Remote did not connect in time.")))
        let task = Task { @MainActor in
            do {
                let fd = try await UURemoteConnections.shared.openStream(to: machine.uuTarget, host: host, port: port, timeout: .seconds(timeout))
                result.withLock { $0 = .success(fd) }
            } catch {
                // Nothing listens there: on a Mac, Remote Login is off.
                let failure = UURemoteFailure("\(machine.name) did not accept a connection to port \(port) through UU Remote (\(error.localizedDescription)). Turn on SSH on the device (on a Mac: System Settings › General › Sharing › Remote Login).")
                result.withLock { $0 = .failure(failure) }
            }
            done.signal()
        }
        // Joining the device's room takes longer than a TCP connect.
        guard done.wait(timeout: .now() + max(timeout, 30) + 5) == .success else {
            task.cancel()
            return .failure(UURemoteFailure("UU Remote did not connect in \(Int(max(timeout, 30))) seconds."))
        }
        return result.withLock { $0 }
    }
}
