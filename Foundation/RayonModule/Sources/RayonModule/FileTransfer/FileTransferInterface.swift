//
//  FileTransferInterface.swift
//  RayonModule
//
//  Platform UI handler used by the shared file transfer core. Each app
//  registers its implementation at launch before any transfer starts.
//

import Foundation
import os

public protocol FileTransferUIHandler: AnyObject, Sendable {
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
    private static let storage = OSAllocatedUnfairLock<FileTransferUIHandler>(initialState: DefaultFileTransferUIHandler())

    /// Registered once at app launch and read afterwards from any queue;
    /// the lock keeps a late read from racing the registration.
    public static var uiHandler: FileTransferUIHandler {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
