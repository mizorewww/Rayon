//
//  SSHConnection+Session.swift
//  RayonSSH
//
//  Shells and commands on session channels. A command's exit status is
//  what the server reported; a command that ends without one, is killed by
//  a signal or runs out of time is an error, never a success.
//

import Foundation
import NIOCore
import os
@preconcurrency import NIOSSH

public struct SSHExecResult: Sendable {
    public var status: Int32
    public var output: Data
    public var errorOutput: Data
}

public extension SSHConnection {
    /// Runs `command` and collects what it prints.
    func execute(_ command: String, timeout: Duration? = nil) async throws -> SSHExecResult {
        let collected = OutputCollector()
        let status = try await execute(command, timeout: timeout) { chunk, isError in
            await collected.append(chunk, isError: isError)
        }
        return await SSHExecResult(status: status, output: collected.output, errorOutput: collected.errorOutput)
    }

    /// Runs `command`, handing its output over as it arrives, and returns
    /// its exit status. The next output is read once `output` returns.
    func execute(
        _ command: String,
        timeout: Duration? = nil,
        output: @escaping @Sendable (_ chunk: ByteBuffer, _ isError: Bool) async -> Void
    ) async throws -> Int32 {
        let session = try await openSession()
        let run: @Sendable () async throws -> Int32 = {
            try await session.executeThenClose { inbound, _ in
                try await session.channel.triggerUserOutboundEvent(
                    SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
                ).get()
                var status: Int32?
                var signal: String?
                for try await event in inbound {
                    switch event {
                    case let .output(chunk): await output(chunk, false)
                    case let .errorOutput(chunk): await output(chunk, true)
                    case .requestRejected: throw SSHError.channelRejected("The server refused to run the command.")
                    case .requestAccepted: break
                    case let .exitStatus(code): status = code
                    case let .exitSignal(name): signal = name
                    }
                }
                if let status { return status }
                if let signal { throw SSHError.channelRejected("The command was killed by SIG\(signal).") }
                throw SSHError.noExitStatus
            }
        }
        // The server only confirms a close once the command has ended, so
        // a timed-out or cancelled command is abandoned, not waited for.
        return try await abandoning(run, after: timeout) {
            session.channel.close(promise: nil)
        }
    }

    /// Opens an interactive shell on a pseudo-terminal.
    func openShell(terminalType: String, columns: Int, rows: Int) async throws -> SSHShell {
        let session = try await openSession()
        let channel = session.channel
        do {
            try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: terminalType,
                terminalCharacterWidth: columns,
                terminalRowHeight: rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:])
            )).get()
            try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true)).get()
        } catch {
            channel.close(promise: nil)
            throw SSHError.channelRejected("The server would not start a shell (\(SSHTransport.describe(error))).")
        }
        return SSHShell(session: session)
    }
}

/// An interactive shell. `run` drives it until the shell ends.
public struct SSHShell: Sendable {
    let session: NIOAsyncChannel<SSHSessionEvent, ByteBuffer>

    /// Sends what comes from `input` and hands output to `output` until the
    /// shell exits; returns its exit status when the server reported one.
    public func run(
        input: AsyncStream<ByteBuffer>,
        output: @escaping @Sendable (ByteBuffer) async -> Void
    ) async throws -> Int32? {
        try await session.executeThenClose { inbound, outbound in
            try await withThrowingTaskGroup(of: Int32?.self) { group in
                group.addTask {
                    for await chunk in input {
                        try await outbound.write(chunk)
                    }
                    return nil
                }
                var status: Int32?
                var rejected = 0
                for try await event in inbound {
                    switch event {
                    case let .output(chunk), let .errorOutput(chunk): await output(chunk)
                    case .requestRejected:
                        rejected += 1
                        throw SSHError.channelRejected("The server refused a pseudo-terminal or a shell.")
                    case .requestAccepted: break
                    case let .exitStatus(code): status = code
                    case .exitSignal: break
                    }
                }
                group.cancelAll()
                return status
            }
        }
    }

    /// Tells the server the terminal's new size.
    public func resize(columns: Int, rows: Int) {
        session.channel.triggerUserOutboundEvent(
            SSHChannelRequestEvent.WindowChangeRequest(
                terminalCharacterWidth: columns, terminalRowHeight: rows, terminalPixelWidth: 0, terminalPixelHeight: 0
            ),
            promise: nil
        )
    }

    /// Ends the shell from this side.
    public func close() {
        session.channel.close(promise: nil)
    }
}

private actor OutputCollector {
    var output = Data()
    var errorOutput = Data()

    func append(_ chunk: ByteBuffer, isError: Bool) {
        if isError { errorOutput.append(contentsOf: chunk.readableBytesView) } else { output.append(contentsOf: chunk.readableBytesView) }
    }
}

/// The result of `operation`, unless `timeout` passes or the caller is
/// cancelled first; then `abandon` runs and this returns at once with
/// `SSHError.timedOut` or `CancellationError`, leaving the operation to wind
/// down on its own.
func abandoning<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T,
    after timeout: Duration?,
    abandon: @escaping @Sendable () -> Void
) async throws -> T {
    let state = OSAllocatedUnfairLock(initialState: AbandonState<T>.running)
    // The first outcome wins; it reaches the caller whether or not it is
    // already waiting.
    let finish: @Sendable (Result<T, Error>) -> Void = { result in
        let continuation = state.withLock { (state: inout AbandonState<T>) -> CheckedContinuation<T, Error>? in
            switch state {
            case .running:
                state = .finished(result)
                return nil
            case let .waiting(continuation):
                state = .delivered
                return continuation
            case .finished, .delivered:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
    let work = Task {
        do { finish(.success(try await operation())) } catch { finish(.failure(error)) }
    }
    let timer = Task {
        guard let timeout else { return }
        try await Task.sleep(for: timeout)
        abandon()
        work.cancel()
        finish(.failure(SSHError.timedOut))
    }
    defer { timer.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let early = state.withLock { (state: inout AbandonState<T>) -> Result<T, Error>? in
                if case let .finished(result) = state {
                    state = .delivered
                    return result
                }
                state = .waiting(continuation)
                return nil
            }
            if let early { continuation.resume(with: early) }
        }
    } onCancel: {
        abandon()
        work.cancel()
        finish(.failure(CancellationError()))
    }
}

private enum AbandonState<T: Sendable>: Sendable {
    case running
    case waiting(CheckedContinuation<T, Error>)
    case finished(Result<T, Error>)
    case delivered
}
