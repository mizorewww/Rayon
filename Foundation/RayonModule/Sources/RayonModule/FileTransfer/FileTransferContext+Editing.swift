//
//  FileTransferContext+Editing.swift
//  RayonModule
//
//  Reading a remote file as text and writing it back, for the editor. Both go
//  through the session's SFTP connection and a private temporary folder that is
//  removed afterwards.
//

import Foundation
import RayonSSH

public enum RemoteTextFileError: LocalizedError, Equatable {
    case notConnected
    case tooLarge(bytes: Int64, limit: Int64)
    case notText
    case transfer(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "Not connected to the server.", bundle: .module)
        case let .tooLarge(bytes, limit):
            let formatter = ByteCountFormatter()
            return String(localized: "This file is \(formatter.string(fromByteCount: bytes)); files up to \(formatter.string(fromByteCount: limit)) open in the editor. Download it instead.", bundle: .module)
        case .notText:
            return String(localized: "This file isn't UTF-8 text, so it can't be edited here. Download it instead.", bundle: .module)
        case let .transfer(message):
            return message
        }
    }
}

public extension FileTransferContext {
    /// Files larger than this are downloaded rather than opened in the editor.
    nonisolated static let editableSizeLimit: Int64 = 4 * 1024 * 1024

    /// A folder listing in the order the file lists show it: folders first,
    /// then by name as Finder sorts.
    nonisolated static func sortedForDisplay(_ list: [RemoteFile]) -> [RemoteFile] {
        // The kind is read once per file, not once per comparison.
        var keyed = list.map { (isDirectory: $0.isFolder, file: $0) }
        keyed.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.file.name.localizedStandardCompare(rhs.file.name) == .orderedAscending
        }
        return keyed.map(\.file)
    }

    /// Whether the editor opens `file` (a file, or a link to one, within
    /// the size limit).
    nonisolated static func isEditable(_ file: RemoteFile) -> Bool {
        !file.isFolder && ((file.linkTarget ?? file.fstat).size ?? 0) <= editableSizeLimit
    }

    /// Reads a remote file as UTF-8 text, after the operations queued before.
    func readText(at remotePath: String) async throws -> String {
        if !connected && !processConnection {
            processBootstrap()
            let changes = $connected
                .combineLatest($processConnection)
                .timeout(.seconds(30), scheduler: DispatchQueue.main)
                .values
            for await (connected, connecting) in changes where connected || !connecting || destroyedSession {
                break
            }
        }
        guard connected else { throw RemoteTextFileError.notConnected }
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = folder.appendingPathComponent(URL(fileURLWithPath: remotePath).lastPathComponent)
        try await perform { sftp in
            let size = try await sftp.entry(at: remotePath).size
            if let size, size > Self.editableSizeLimit {
                throw RemoteTextFileError.tooLarge(bytes: size, limit: Self.editableSizeLimit)
            }
            do {
                try await sftp.download(remotePath, to: local) { _ in }
            } catch {
                throw RemoteTextFileError.transfer(Self.describe(error, String(localized: "Couldn't read \(remotePath)", bundle: .module)))
            }
        }
        let data = try Data(contentsOf: local)
        guard Int64(data.count) <= Self.editableSizeLimit else {
            throw RemoteTextFileError.tooLarge(bytes: Int64(data.count), limit: Self.editableSizeLimit)
        }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw RemoteTextFileError.notText
        }
        return text
    }

    /// Replaces a remote file's contents with `text` (UTF-8), after the
    /// operations queued before.
    func writeText(_ text: String, to remotePath: String) async throws {
        guard connected else { throw RemoteTextFileError.notConnected }
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let remote = URL(fileURLWithPath: remotePath)
        let local = folder.appendingPathComponent(remote.lastPathComponent)
        try Data(text.utf8).write(to: local)
        let directory = remote.deletingLastPathComponent().path
        try await perform { sftp in
            do {
                try await sftp.upload(local, toDirectory: directory) { _ in }
            } catch {
                throw RemoteTextFileError.transfer(Self.describe(error, String(localized: "Couldn't save \(remotePath)", bundle: .module)))
            }
        }
    }

    private static func makeScratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RayonEditor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Runs `work` in the session's queue and hands back how it ended.
    private func perform(_ work: @escaping @Sendable (SFTPSession) async throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            enqueue(needsSession: false) { sftp in
                guard let sftp, sftp.isActive else {
                    continuation.resume(throwing: RemoteTextFileError.notConnected)
                    return
                }
                do {
                    try await work(sftp)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
