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
    func debugFile(_ message: String, fileID: String = #fileID) {
        logToFile(.debug, message, fileID: fileID)
    }

    func infoFile(_ message: String, fileID: String = #fileID) {
        logToFile(.info, message, fileID: fileID)
    }

    func errorFile(_ message: String, fileID: String = #fileID) {
        logToFile(.error, message, fileID: fileID)
    }

    private func logToFile(_ level: LogLevel, _ message: String, fileID: String) {
        log(level: level.osLogType, "\(message)")
        LogStore.shared.append(level: level, category: LogCategoryResolver.resolve(fileID: fileID), message: message)
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
