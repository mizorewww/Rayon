//
//  VNCConnection.swift
//  RayonModule
//
//  The TCP transport to a VNC server, on Network.framework.
//

import Foundation
import Network
import os

final class VNCConnection: VNCTransport {
    private let connection: NWConnection

    private init(connection: NWConnection) {
        self.connection = connection
    }

    /// Connects to `host:port`, failing after `timeout` seconds.
    static func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> VNCConnection {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw VNCStreamError.failed("Invalid VNC port \(port)")
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(max(timeout, 1).rounded(.up))
        tcp.noDelay = true // pointer events are tiny and latency-bound
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: NWParameters(tls: nil, tcp: tcp)
        )
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let pending = OSAllocatedUnfairLock<CheckedContinuation<Void, Error>?>(initialState: continuation)
                @Sendable func finish(_ result: Result<Void, Error>) {
                    pending.withLock { pending in
                        defer { pending = nil }
                        return pending
                    }?.resume(with: result)
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(.success(()))
                    case let .waiting(error), let .failed(error):
                        // `waiting` means no path or a refused connect;
                        // retrying silently would only hide the reason.
                        connection.cancel()
                        finish(.failure(VNCStreamError.failed("Could not connect to \(host):\(port) (\(error.localizedDescription))")))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: DispatchQueue(label: "me.mizorewww.vnc.connection"))
            }
        } onCancel: {
            connection.cancel()
        }
        // From here on, a failure surfaces through receive.
        connection.stateUpdateHandler = nil
        return VNCConnection(connection: connection)
    }

    func receive(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, _, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if let error {
                    continuation.resume(throwing: VNCStreamError.failed(error.localizedDescription))
                } else {
                    // No data and no error: the server closed its side.
                    continuation.resume(throwing: VNCStreamError.endOfStream)
                }
            }
        }
    }

    func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [connection] error in
            if error != nil { connection.cancel() }
        })
    }

    func close() {
        connection.cancel()
    }
}
