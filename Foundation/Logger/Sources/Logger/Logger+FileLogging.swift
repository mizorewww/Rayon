import Foundation
import OSLog

enum LogCategoryResolver {
    /// `os.Logger` does not expose its category, so the file log names the
    /// source file instead: `RayonModule/Sync/CloudSync.swift` reads `CloudSync`.
    static func resolve(fileID: String) -> String {
        let file = fileID.split(separator: "/").last.map(String.init) ?? fileID
        let name = file.split(separator: ".").first.map(String.init) ?? file
        return name.isEmpty ? "App" : name
    }
}

public extension Logger {
    func debugFile(_ message: FileLogMessage, fileID: String = #fileID) {
        logToFile(.debug, message, fileID: fileID)
    }

    func infoFile(_ message: FileLogMessage, fileID: String = #fileID) {
        logToFile(.info, message, fileID: fileID)
    }

    func errorFile(_ message: FileLogMessage, fileID: String = #fileID) {
        logToFile(.error, message, fileID: fileID)
    }

    private func logToFile(_ level: LogLevel, _ message: FileLogMessage, fileID: String) {
        log(level: level.osLogType, "\(message.detail, privacy: .private)")
        LogStore.shared.append(level: level, category: LogCategoryResolver.resolve(fileID: fileID), message: message.file)
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .error: .error
        }
    }
}
