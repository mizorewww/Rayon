//
//  SFTPSession.swift
//  RayonSSH
//
//  An SFTP session on a connection: listing, and recursive upload,
//  download and delete, over Citadel's SFTP client. Transfers report each file's progress and stop between
//  chunks when the caller's task is cancelled.
//

@preconcurrency import Citadel
import Foundation
import NIOCore

/// One directory entry, as the server's `lstat` describes it.
public struct SFTPEntry: Sendable, Hashable {
    public let name: String
    public let size: Int64?
    public let permissions: UInt32?
    public let modificationDate: Date?
    public let ownerUID: UInt32
    public let ownerGID: UInt32

    public init(name: String, attributes: SFTPFileAttributes = .none) {
        self.name = name
        size = attributes.size.map { Int64(clamping: $0) }
        permissions = attributes.permissions
        modificationDate = attributes.accessModificationTime?.modificationTime
        ownerUID = attributes.uidgid?.userId ?? 0
        ownerGID = attributes.uidgid?.groupId ?? 0
    }

    public init(name: String, size: Int64?, permissions: UInt32?, modificationDate: Date?, ownerUID: UInt32 = 0, ownerGID: UInt32 = 0) {
        self.name = name
        self.size = size
        self.permissions = permissions
        self.modificationDate = modificationDate
        self.ownerUID = ownerUID
        self.ownerGID = ownerGID
    }

    private var fileType: UInt32? { permissions.map { $0 & 0o170000 } }
    public var isDirectory: Bool { fileType == 0o040000 }
    public var isLink: Bool { fileType == 0o120000 }
    public var isRegularFile: Bool { fileType == 0o100000 }

    /// "drwxr-xr-x", as `ls -l` prints the mode.
    public var permissionDescription: String {
        guard let permissions else { return "" }
        let kind: Character = isDirectory ? "d" : isLink ? "l" : "-"
        let bits = "rwxrwxrwx"
        return String(kind) + String(bits.enumerated().map { index, flag in
            permissions & (1 << (8 - index)) != 0 ? flag : "-"
        })
    }
}

/// A transfer's progress for the file it is on.
public struct SFTPProgress: Sendable {
    public var file: String
    public var completed: Int64
    public var total: Int64
    public var bytesPerSecond: Int
}

public struct SFTPSession: Sendable {
    /// What one request carries: Citadel cuts writes into 32,000-byte
    /// messages, so a chunk is one message.
    private static let chunkSize = 32000
    /// Requests sent before the first is answered, so a transfer waits
    /// for the round trip once per window rather than once per chunk.
    private static let requestsInFlight = 16
    /// How deep a download descends into folders, as libssh2's did.
    private static let maxDepth = 32

    let client: SFTPClient

    public var isActive: Bool { client.isActive }

    public func close() async {
        try? await client.close()
    }

    public func createDirectory(at path: String) async throws {
        try await client.createDirectory(atPath: path)
    }

    public func rename(_ path: String, to newPath: String) async throws {
        try await client.rename(at: path, to: newPath)
    }

    /// What went wrong, as the server put it when it said.
    public static func describe(_ error: Error) -> String {
        if let status = error as? SFTPMessage.Status { return status.message }
        if case let SFTPError.errorStatus(status) = error { return status.message }
        if let error = error as? SSHError { return error.localizedDescription }
        return SSHTransport.describe(error)
    }

    /// The entries of a directory, without "." and "..", and without
    /// names no file can have: a server that lists "../../.zshrc" would
    /// have a download write outside the folder it goes to (CVE-2019-6111).
    public func entries(at path: String) async throws -> [SFTPEntry] {
        try await client.listDirectory(atPath: path)
            .flatMap(\.components)
            .filter { Self.isFileName($0.filename) }
            .map { SFTPEntry(name: $0.filename, attributes: $0.attributes) }
    }

    /// Whether `name` is one path component. Control characters are out:
    /// URL drops a NUL, so "..\0" would become "..".
    static func isFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    public func entry(at path: String) async throws -> SFTPEntry {
        try await SFTPEntry(name: (path as NSString).lastPathComponent, attributes: client.getAttributes(at: path))
    }

    /// Copies a local file or folder into `directory`. Links to files
    /// inside a folder are copied as the files; links to folders are left
    /// out, since they can lead back up.
    public func upload(_ local: URL, toDirectory directory: String, progress: @escaping @Sendable (SFTPProgress) -> Void) async throws {
        let remote = (directory as NSString).appendingPathComponent(local.lastPathComponent)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: local.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: local.path])
        }
        // New files and folders get the local permission bits (less the
        // server's umask), as scp and sftp -p do; existing ones keep theirs.
        let mode = (try? FileManager.default.attributesOfItem(atPath: local.path)[.posixPermissions] as? NSNumber)?
            .map { $0.uint32Value & 0o777 }
        if isDirectory.boolValue {
            let created = (try? await client.getAttributes(at: remote)) == nil
            if created {
                // Writable while its contents go in, as OpenSSH's sftp
                // makes it: a read-only folder gets its mode after.
                try await client.createDirectory(atPath: remote, attributes: Self.attributes(mode.map { $0 | 0o700 }))
            }
            for child in try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                try Task.checkCancellation()
                if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true,
                   (try? child.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != false
                { continue }
                try await upload(child, toDirectory: remote, progress: progress)
            }
            if created, let mode, mode & 0o700 != 0o700, let made = try await client.getAttributes(at: remote).permissions {
                try await client.setAttributes(at: remote, to: Self.attributes(made & 0o7777 & ~(0o700 & ~mode)))
            }
            return
        }
        let handle = try FileHandle(forReadingFrom: local)
        defer { try? handle.close() }
        let total = Int64((try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)??.int64Value ?? 0)
        let (file, readOnly) = try await openForUpload(remote, attributes: Self.attributes(mode))
        let meter = TransferMeter(file: local.lastPathComponent, total: total, report: progress)
        // Each write with the offsets it starts and ends at, oldest first.
        // The writes run concurrently and may reach the server out of order.
        var writes: [(Task<Void, Error>, start: UInt64, end: UInt64)] = []
        // Where everything before has been written.
        var written: UInt64 = 0
        do {
            var offset: UInt64 = 0
            while let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty {
                try Task.checkCancellation()
                if writes.count >= Self.requestsInFlight {
                    let (write, _, end) = writes.removeFirst()
                    try await write.value
                    written = end
                    meter.advance(to: Int64(end))
                }
                let at = offset
                offset += UInt64(data.count)
                writes.append((Task { try await file.write(ByteBuffer(data: data), at: at) }, at, offset))
            }
            while !writes.isEmpty {
                let (write, _, end) = writes.removeFirst()
                try await write.value
                written = end
                meter.advance(to: Int64(end))
            }
            try await file.close()
        } catch {
            for (write, start, end) in writes {
                write.cancel()
                let succeeded = (try? await write.value) != nil
                if succeeded, start == written { written = end }
            }
            // A later write that landed after an earlier one failed would
            // leave a hole of zeros: the file ends where it is whole.
            var size = SFTPFileAttributes()
            size.size = written
            try? await file.setAttributes(to: size)
            try? await file.close()
            if let readOnly { try? await client.setAttributes(at: remote, to: Self.attributes(readOnly)) }
            throw error
        }
        // A read-only file written over is read-only again.
        if let readOnly { try await client.setAttributes(at: remote, to: Self.attributes(readOnly)) }
    }

    /// Opens `remote` to be written over. An existing read-only file of
    /// this user's is made writable for it; its mode is returned to be
    /// put back once it is written.
    private func openForUpload(_ remote: String, attributes: SFTPFileAttributes) async throws -> (SFTPFile, readOnly: UInt32?) {
        let flags: SFTPOpenFileFlags = [.write, .create, .truncate]
        do {
            return try await (client.openFile(filePath: remote, flags: flags, attributes: attributes), nil)
        } catch {
            guard let existing = try? await client.getAttributes(at: remote).permissions.map({ $0 & 0o7777 }),
                  existing & 0o200 == 0,
                  (try? await client.setAttributes(at: remote, to: Self.attributes(existing | 0o200))) != nil
            else { throw error }
            do {
                return try await (client.openFile(filePath: remote, flags: flags, attributes: attributes), existing)
            } catch {
                try? await client.setAttributes(at: remote, to: Self.attributes(existing))
                throw error
            }
        }
    }

    private static func attributes(_ permissions: UInt32?) -> SFTPFileAttributes {
        var attributes = SFTPFileAttributes()
        attributes.permissions = permissions
        return attributes
    }

    /// Copies a remote file or folder to `local`, which must not exist.
    /// Links to files inside a folder are copied as the files; links to
    /// folders are left out, since they can lead back up.
    public func download(_ remote: String, to local: URL, progress: @escaping @Sendable (SFTPProgress) -> Void) async throws {
        try await download(remote, to: local, depth: 0, progress: progress)
    }

    private func download(_ remote: String, to local: URL, depth: Int, progress: @escaping @Sendable (SFTPProgress) -> Void) async throws {
        let attributes = try await client.getAttributes(at: remote)
        if SFTPEntry(name: "", attributes: attributes).isDirectory {
            guard depth < Self.maxDepth else {
                throw CocoaError(.fileReadUnknown, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "\(remote) is more than \(Self.maxDepth) folders deep.", bundle: .module),
                ])
            }
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            for entry in try await entries(at: remote) {
                try Task.checkCancellation()
                let path = (remote as NSString).appendingPathComponent(entry.name)
                // The listing describes a link itself; what it points to decides.
                if entry.isLink, (try? await self.entry(at: path))?.isDirectory != false { continue }
                let child = local.appendingPathComponent(entry.name)
                // However URL reads the name, the file lands in this folder.
                guard child.lastPathComponent == entry.name,
                      child.deletingLastPathComponent().standardizedFileURL.path == local.standardizedFileURL.path
                else { continue }
                try await download(path, to: child, depth: depth + 1, progress: progress)
            }
            return
        }
        guard FileManager.default.createFile(atPath: local.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: local.path])
        }
        let handle = try FileHandle(forWritingTo: local)
        defer { try? handle.close() }
        let file = try await client.openFile(filePath: remote, flags: .read)
        let meter = TransferMeter(file: local.lastPathComponent, total: Int64(clamping: attributes.size ?? 0), report: progress)
        // Reads ahead of the one being written, oldest first.
        var reads: [Task<ByteBuffer, Error>] = []
        do {
            var requested: UInt64 = 0
            var offset: UInt64 = 0
            while true {
                while reads.count < Self.requestsInFlight {
                    let from = requested
                    reads.append(Task { try await Self.read(file, from: from) })
                    requested += UInt64(Self.chunkSize)
                }
                try Task.checkCancellation()
                let chunk = try await reads.removeFirst().value
                try handle.write(contentsOf: chunk.readableBytesView)
                offset += UInt64(chunk.readableBytes)
                meter.advance(to: Int64(offset))
                // Only the end of the file answers short.
                if chunk.readableBytes < Self.chunkSize { break }
            }
            for read in reads { read.cancel(); _ = await read.result }
            try await file.close()
        } catch {
            for read in reads { read.cancel(); _ = await read.result }
            try? await file.close()
            throw error
        }
    }

    /// The chunk at `offset`, whole unless the file ends in it: a server
    /// may answer a read with fewer bytes than asked for.
    private static func read(_ file: SFTPFile, from offset: UInt64) async throws -> ByteBuffer {
        var chunk = try await file.read(from: offset, length: UInt32(chunkSize))
        while chunk.readableBytes > 0, chunk.readableBytes < chunkSize {
            var more = try await file.read(from: offset + UInt64(chunk.readableBytes), length: UInt32(chunkSize - chunk.readableBytes))
            guard more.readableBytes > 0 else { break }
            chunk.writeBuffer(&more)
        }
        return chunk
    }

    /// Deletes a remote file, link or folder with everything in it.
    /// A link is removed itself, never what it points to.
    public func removeItem(at path: String, onItem: @escaping @Sendable (String) -> Void) async throws {
        let entry = try await SFTPEntry(name: (path as NSString).lastPathComponent, attributes: client.getLinkAttributes(at: path))
        onItem(path)
        guard entry.isDirectory else {
            try await client.remove(at: path)
            return
        }
        for child in try await entries(at: path) {
            try Task.checkCancellation()
            let childPath = (path as NSString).appendingPathComponent(child.name)
            if child.isDirectory {
                try await removeItem(at: childPath, onItem: onItem)
            } else {
                onItem(childPath)
                try await client.remove(at: childPath)
            }
        }
        try await client.rmdir(at: path)
    }
}

/// Reports a file's progress with its average speed so far.
private struct TransferMeter: Sendable {
    let file: String
    let total: Int64
    let report: @Sendable (SFTPProgress) -> Void
    let started = Date()

    init(file: String, total: Int64, report: @escaping @Sendable (SFTPProgress) -> Void) {
        self.file = file
        self.total = total
        self.report = report
        report(SFTPProgress(file: file, completed: 0, total: total, bytesPerSecond: 0))
    }

    func advance(to completed: Int64) {
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        report(SFTPProgress(file: file, completed: completed, total: max(total, completed), bytesPerSecond: Int(Double(completed) / elapsed)))
    }
}
