@_exported import Foundation
@_exported import OSLog

public extension Logger {
    private static let loggingSubsystem: String = {
        if let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty {
            return identifier
        }
        return ProcessInfo.processInfo.processName
    }()

    static let app = Logger(subsystem: loggingSubsystem, category: "App")
    static let ui = Logger(subsystem: loggingSubsystem, category: "UI")
    static let database = Logger(subsystem: loggingSubsystem, category: "Database")
    static let syncEngine = Logger(subsystem: loggingSubsystem, category: "SyncEngine")
    static let network = Logger(subsystem: loggingSubsystem, category: "Network")
    static let terminal = Logger(subsystem: loggingSubsystem, category: "Terminal")
    static let remoteDesktop = Logger(subsystem: loggingSubsystem, category: "RemoteDesktop")
}
