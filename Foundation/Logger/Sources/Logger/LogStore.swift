import Foundation

/// A rolling plain-text log in `Documents/Logs`, what the in-app log viewer
/// reads and shares. All file access runs on one serial queue.
public final class LogStore: Sendable {
    public static let shared = LogStore()

    private let queue = DispatchQueue(label: "me.mizorewww.rayon.logstore", qos: .utility)
    private let maxFileSize: Int
    private let maxFiles: Int
    let logDirectory: URL
    /// Off for a test runner or command-line tool, which would otherwise
    /// write into the user's own Documents folder; an app writes into its own.
    let writesFile: Bool
    private static let logFileName = "Rayon.log"

    public init(
        directory: URL? = nil,
        maxFileSize: Int = 5 * 1024 * 1024,
        maxFiles: Int = 5
    ) {
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
        logDirectory = Self.logDirectory(baseDirectory: directory ?? Self.defaultBaseDirectory())
        writesFile = directory != nil || Bundle.main.bundleURL.pathExtension == "app"
        guard writesFile else { return }
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    /// The current log file, for sharing it as a file.
    public var logFileURL: URL {
        logDirectory.appendingPathComponent(Self.logFileName)
    }

    public func append(level: LogLevel, category: String, message: String) {
        guard writesFile else { return }
        let timestamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
        let line = Data("\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n".utf8)
        queue.async { [self] in
            do {
                try ensureLogFileExists()
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try rotateIfNeeded()
            } catch {
                // A failed disk write must never take the logging caller down.
            }
        }
    }

    public func readTail(maxBytes: Int = 128 * 1024) -> String {
        queue.sync {
            guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return "" }
            defer { try? handle.close() }

            let fileSize = (try? handle.seekToEnd()) ?? 0
            let startOffset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
            try? handle.seek(toOffset: startOffset)
            let data = (try? handle.readToEnd()) ?? Data()
            // The byte cut can land inside a multi-byte character; skip its continuation bytes.
            let body = startOffset > 0 ? data.drop(while: { $0 & 0xC0 == 0x80 }) : data
            return String(decoding: body, as: UTF8.self)
        }
    }

    public func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: logFileURL)
            for index in 1 ... maxFiles {
                try? FileManager.default.removeItem(at: rotatedFileURL(index: index))
            }
        }
    }

    public func flush() {
        queue.sync {}
    }

    private func ensureLogFileExists() throws {
        guard !FileManager.default.fileExists(atPath: logFileURL.path) else { return }
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }

    private func rotateIfNeeded() throws {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue >= maxFileSize else { return }

        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let destination = rotatedFileURL(index: index + 1)
            try? fileManager.removeItem(at: destination)
            try? fileManager.moveItem(at: rotatedFileURL(index: index), to: destination)
        }

        let first = rotatedFileURL(index: 1)
        try? fileManager.removeItem(at: first)
        try fileManager.moveItem(at: logFileURL, to: first)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }

    func rotatedFileURL(index: Int) -> URL {
        logDirectory.appendingPathComponent("\(Self.logFileName).\(index)")
    }

    static func defaultBaseDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func logDirectory(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent("Logs", isDirectory: true)
    }
}
