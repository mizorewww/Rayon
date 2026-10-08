//
//  FileTransferInterface.swift
//  RayonModule
//
//  Platform UI handler used by the shared file transfer core. Each app
//  registers its implementation at launch before any transfer starts.
//

import Foundation

public protocol FileTransferUIHandler: AnyObject {
    /// Present an error message to the user.
    func presentError(_ message: String)

    /// Ask the user to confirm an action, calling the completion with the result.
    func requiresConfirmation(_ message: String, completion: @escaping (Bool) -> Void)

    /// Called on the first successful connection bootstrap; iOS uses it to
    /// auto-open the transfer interface. Called on the main thread.
    func autoOpenInterface(_ context: FileTransferContext)

    /// Called after a download completes successfully.
    func downloadCompleted()
}

public extension FileTransferUIHandler {
    func presentError(_ message: String) {
        debugPrint("<FileTransferError> \(message)")
    }

    func requiresConfirmation(_: String, completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func autoOpenInterface(_: FileTransferContext) {}

    func downloadCompleted() {}
}

private final class DefaultFileTransferUIHandler: FileTransferUIHandler {}

public enum FileTransferInterface {
    // Registered once at app launch and only read afterwards;
    // nonisolated(unsafe) matches the codebase's singleton conventions.
    nonisolated(unsafe) public static var uiHandler: FileTransferUIHandler = DefaultFileTransferUIHandler()
}
