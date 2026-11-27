//
//  UURemote+SSH.swift
//  RayonModule
//
//  SSH (and SFTP, port forwards) to a UU device: the connection's socket is
//  a UURemoteKit port-mapped stream to the device's own sshd. Opening it
//  only awaits the kit; nothing blocks a thread.
//

import Darwin
import Foundation
import UURemoteKit

extension RDMachine {
    /// A port-mapped stream to the device's sshd, made over the device's
    /// connection, which is made for it if there is none and kept while the
    /// stream is open. A stream that arrives after the caller gave up is
    /// closed, which lets the device's connection go.
    func openUUSSHStream(timeout: Duration) async throws -> Int32 {
        let port = UInt16(Int(remotePort) ?? 22)
        // A UU server's address is its device id, not an IP: the service is
        // on the device's own loopback. Only a dotted address is forwarded.
        let host = (remoteAddress == uuDeviceID || !remoteAddress.contains(".")) ? "127.0.0.1" : remoteAddress
        let target = uuTarget
        let name = name
        let descriptor: Int32
        do {
            descriptor = try await UURemoteConnections.shared.openStream(
                to: target, host: host, port: port, timeout: max(timeout, .seconds(15))
            )
        } catch let failure as UUPortMappingFailure where Self.isRefusal(failure) {
            // The device answered and nothing listens there: on a Mac,
            // Remote Login is off.
            throw SSHFailure(
                message: String(localized: "\(name) did not accept a connection to port \(port) through UU Remote (\(failure.message)). Turn on SSH on the device (on a Mac: System Settings › General › Sharing › Remote Login).", bundle: .module),
                unreachable: true
            )
        } catch {
            throw SSHFailure(message: String(localized: "Could not reach \(name) through UU Remote: \(error.localizedDescription)", bundle: .module), unreachable: true)
        }
        if Task.isCancelled {
            Darwin.close(descriptor)
            throw CancellationError()
        }
        return descriptor
    }

    /// The host's own answer to the port mapping, as opposed to the kit
    /// giving up (a closed connection, no answer in time).
    private static func isRefusal(_ failure: UUPortMappingFailure) -> Bool {
        let local = [
            "The UU Remote connection closed.",
            "The host did not answer the port mapping in time.",
            "The UU Remote connection is not ready for port mapping.",
        ]
        return !local.contains(failure.message) && !failure.message.hasPrefix("Could not make a socket pair")
    }
}
