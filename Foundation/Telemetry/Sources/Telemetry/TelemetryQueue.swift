//
//  TelemetryQueue.swift
//  Telemetry
//
//  Reports waiting to be sent: one JSON file each in
//  Application Support/<bundle id>/Telemetry/pending, the oldest dropped past 14.
//

import Foundation

public struct TelemetryQueue: Sendable {
    public static let capacity = 14

    let directory: URL
    /// A copy of the last report the server took, for "View What's Sent".
    let lastSentFile: URL

    init(root: URL) {
        directory = root.appending(path: "pending", directoryHint: .isDirectory)
        lastSentFile = root.appending(path: "last-sent.json")
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func prettyEncoder() -> JSONEncoder {
        let encoder = encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        return encoder
    }

    public struct Entry: Sendable {
        let file: URL
        public let report: TelemetryReport
    }

    func enqueue(_ report: TelemetryReport) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Names sort in the order the reports were made.
        let stamp = String(format: "%015llu", UInt64(Date().timeIntervalSince1970 * 1000))
        let file = directory.appending(path: "\(stamp)-\(report.nonce.uuidString).json")
        try Self.encoder().encode(report).write(to: file, options: .atomic)
        let files = self.files()
        for stale in files.dropLast(Self.capacity) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return names.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every readable pending report, oldest first; unreadable files are dropped.
    public func entries() -> [Entry] {
        files().compactMap { file in
            guard let data = try? Data(contentsOf: file), let report = try? JSONDecoder().decode(TelemetryReport.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            return Entry(file: file, report: report)
        }
    }

    func remove(_ entries: [Entry]) {
        for entry in entries {
            try? FileManager.default.removeItem(at: entry.file)
        }
    }

    /// Drops what a lower level no longer allows: whole reports above it.
    func trim(to level: TelemetryLevel) {
        guard level > .off else {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: lastSentFile)
            return
        }
        remove(entries().filter { $0.report.level > level })
    }

    func recordSent(_ report: TelemetryReport) {
        try? Self.encoder().encode(report).write(to: lastSentFile, options: .atomic)
    }

    public func lastSent() -> TelemetryReport? {
        (try? Data(contentsOf: lastSentFile)).flatMap { try? JSONDecoder().decode(TelemetryReport.self, from: $0) }
    }
}
