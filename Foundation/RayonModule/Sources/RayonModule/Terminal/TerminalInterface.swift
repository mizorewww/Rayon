//
//  TerminalInterface.swift
//  RayonModule
//
//  Platform UI handler used by the shared terminal session core. Each app
//  registers its implementation before any session starts.
//

import Foundation
import os

public protocol TerminalUIHandler: AnyObject, Sendable {
    /// Called on the first connection bootstrap when the store asks to open
    /// interfaces automatically; iOS uses it to auto-present the terminal.
    /// Called on the main thread.
    func autoOpenInterface(_ context: TerminalContext)
}

public extension TerminalUIHandler {
    func autoOpenInterface(_: TerminalContext) {}
}

private final class DefaultTerminalUIHandler: TerminalUIHandler {}

public enum TerminalInterface {
    private static let storage = OSAllocatedUnfairLock<TerminalUIHandler>(initialState: DefaultTerminalUIHandler())

    /// Registered once at app launch and only read afterwards; the lock
    /// keeps a late read from racing the registration.
    public static var uiHandler: TerminalUIHandler {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
