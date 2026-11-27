//
//  FixedTreeSFTP.swift
//  RayonSSHTests
//
//  An SFTP server's file system as a dictionary: folders by path, each
//  listing whatever names the test gives it, "../x" included. It counts
//  the folders opened and still open.
//

@preconcurrency import Citadel
import Foundation
import NIOCore
import Synchronization

final class FixedTreeSFTP: SFTPDelegate {
    /// What a folder lists: a name, and a file's contents, or nil for a folder.
    typealias Listing = [(name: String, contents: String?)]

    private let tree: [String: Listing]
    private let opened = Mutex<[String]>([])
    private let open = Mutex(0)
    private let removed = Mutex<[String]>([])

    init(_ tree: [String: Listing]) {
        self.tree = tree
    }

    /// The folders opened for listing, in order.
    var openedFolders: [String] { opened.withLock { $0 } }
    /// Folder handles the client has not closed.
    var openFolderHandles: Int { open.withLock { $0 } }
    var removedPaths: [String] { removed.withLock { $0 } }

    private func contents(of path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        return tree[parent]?.first { $0.name == name }?.contents
    }

    func fileAttributes(atPath path: String, context _: SSHContext) async throws -> SFTPFileAttributes {
        var attributes = SFTPFileAttributes()
        if tree[path] != nil {
            attributes.permissions = 0o040755
        } else {
            attributes.permissions = 0o100644
            attributes.size = UInt64(contents(of: path)?.utf8.count ?? 0)
        }
        return attributes
    }

    func openFile(_ filePath: String, withAttributes _: SFTPFileAttributes, flags _: SFTPOpenFileFlags, context _: SSHContext) async throws -> SFTPFileHandle {
        File(data: Data((contents(of: filePath) ?? "").utf8))
    }

    func removeFile(_ filePath: String, context _: SSHContext) async throws -> SFTPStatusCode {
        removed.withLock { $0.append(filePath) }
        return .ok
    }

    func createDirectory(_: String, withAttributes _: SFTPFileAttributes, context _: SSHContext) async throws -> SFTPStatusCode {
        .permissionDenied
    }

    func removeDirectory(_ filePath: String, context _: SSHContext) async throws -> SFTPStatusCode {
        removed.withLock { $0.append(filePath) }
        return .ok
    }

    func realPath(for canonicalUrl: String, context _: SSHContext) async throws -> [SFTPPathComponent] {
        [SFTPPathComponent(filename: canonicalUrl, longname: canonicalUrl, attributes: .none)]
    }

    func openDirectory(atPath path: String, context _: SSHContext) async throws -> SFTPDirectoryHandle {
        opened.withLock { $0.append(path) }
        open.withLock { $0 += 1 }
        let components = (tree[path] ?? []).map { entry in
            var attributes = SFTPFileAttributes()
            attributes.permissions = entry.contents == nil ? 0o040755 : 0o100644
            attributes.size = UInt64(entry.contents?.utf8.count ?? 0)
            return SFTPPathComponent(filename: entry.name, longname: entry.name, attributes: attributes)
        }
        return Folder(listing: [SFTPFileListing(path: components)], owner: self)
    }

    func setFileAttributes(to _: SFTPFileAttributes, atPath _: String, context _: SSHContext) async throws -> SFTPStatusCode {
        .ok
    }

    func addSymlink(linkPath _: String, targetPath _: String, context _: SSHContext) async throws -> SFTPStatusCode {
        .permissionDenied
    }

    func readSymlink(atPath path: String, context _: SSHContext) async throws -> [SFTPPathComponent] {
        [SFTPPathComponent(filename: path, longname: path, attributes: .none)]
    }

    func rename(oldPath _: String, newPath _: String, flags _: UInt32, context _: SSHContext) async throws -> SFTPStatusCode {
        .permissionDenied
    }

    /// Held by the server until the client closes it.
    private final class Folder: SFTPDirectoryHandle {
        let listing: [SFTPFileListing]
        let owner: FixedTreeSFTP

        init(listing: [SFTPFileListing], owner: FixedTreeSFTP) {
            self.listing = listing
            self.owner = owner
        }

        func listFiles(context _: SSHContext) async throws -> [SFTPFileListing] { listing }

        deinit { owner.open.withLock { $0 -= 1 } }
    }

    private struct File: SFTPFileHandle {
        let data: Data

        func read(at offset: UInt64, length: UInt32) async throws -> ByteBuffer {
            guard offset < data.count else { return ByteBuffer() }
            let end = min(data.count, Int(offset) + Int(length))
            return ByteBuffer(data: data[Int(offset) ..< end])
        }

        func write(_: ByteBuffer, atOffset _: UInt64) async throws -> SFTPStatusCode { .permissionDenied }
        func close() async throws -> SFTPStatusCode { .ok }
        func readFileAttributes() async throws -> SFTPFileAttributes {
            var attributes = SFTPFileAttributes()
            attributes.size = UInt64(data.count)
            return attributes
        }

        func setFileAttributes(to _: SFTPFileAttributes) async throws {}
    }
}
