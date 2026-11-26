//
//  SnippetExecSession.swift
//  RayonModule
//
//  Shared one-server snippet run, previously duplicated between the
//  macOS and iOS apps. Output sinks are injected, so each app keeps its
//  own presentation; the CRLF cleanup xterm needs lives here once.
//

import Foundation
import NSRemoteShell

/// One snippet run against one server: connect, authenticate, execute,
/// stream. Synchronous; drive it from a background queue.
public class SnippetExecSession {
    /// How a run ended.
    public enum Outcome {
        case completed
        case connectFailed
        case authenticateFailed
    }

    public let machine: RDMachine
    public let shell: NSRemoteShell

    public init(machine: RDMachine, shell: NSRemoteShell) {
        self.machine = machine
        self.shell = shell
    }

    /// Runs `code` on the server, streaming output to `onOutput` after the
    /// CRLF cleanup. Returns after the command ends or the continuation
    /// handler stops it.
    @discardableResult
    public func execute(
        _ code: String,
        onBegin: @escaping () -> Void = {},
        onOutput: @escaping (String) -> Void,
        withContinuationHandler shouldContinue: @escaping () -> Bool
    ) -> Outcome {
        shell.requestConnectAndWait()
        guard shell.isConnected else { return .connectFailed }
        // A server without an associated identity falls back to the
        // store's auto identities instead of failing outright. Reads are
        // the store's worker snapshot: runs happen on background queues.
        if let identity = RayonStore.shared.workerAssociatedIdentity(for: machine) {
            identity.callAuthenticationWith(remote: shell)
        } else {
            shell.authenticateWithAutoIdentities(RayonStore.shared.workerIdentitiesForAutoAuth)
        }
        guard shell.isConnected, shell.isAuthenticated else { return .authenticateFailed }
        shell.beginExecute(
            withCommand: code,
            withTimeout: 0
        ) {
            onBegin()
        } withOutput: { output in
            onOutput(Self.cleanForTerminal(output))
        } withContinuationHandler: {
            shouldContinue()
        }
        return .completed
    }

    /// xterm picks the output up, so \n becomes \r\n without doubling \r.
    static func cleanForTerminal(_ output: String) -> String {
        output
            .replacingOccurrences(of: "\n", with: "\r\n") // \n -> \r\n, \r\n -> \r\r\n
            .replacingOccurrences(of: "\r\r\n", with: "\r\n") // \r\r -> \n
    }
}
