//
//  FileTransferLinkTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import RayonSSH
import XCTest

final class FileTransferLinkTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/srv")

    private func entry(_ name: String, type: UInt32, size: Int64 = 0) -> SFTPEntry {
        SFTPEntry(name: name, size: size, permissions: type | 0o755, modificationDate: nil)
    }

    func testALinkToAFolderOpensAsAFolder() {
        let link = entry("data", type: 0o120000, size: 9)
        let folder = FileTransferContext.RemoteFile(base: base, name: "data", fstat: link, linkTarget: entry("data", type: 0o040000))
        XCTAssertTrue(folder.isFolder)
        XCTAssertFalse(FileTransferContext.isEditable(folder))
        let file = FileTransferContext.RemoteFile(base: base, name: "a", fstat: entry("a", type: 0o100000))
        XCTAssertEqual([file, folder].sorted(using: RemoteFileComparator(.name)).map(\.name), ["data", "a"])
    }

    func testABrokenOrLoopingLinkIsNoFolder() {
        let link = FileTransferContext.RemoteFile(base: base, name: "loop", fstat: entry("loop", type: 0o120000, size: 4))
        XCTAssertFalse(link.isFolder)
        XCTAssertTrue(FileTransferContext.isEditable(link))
    }

    func testALinkToABigFileIsNotEdited() {
        let target = entry("big", type: 0o100000, size: FileTransferContext.editableSizeLimit + 1)
        let link = FileTransferContext.RemoteFile(base: base, name: "big", fstat: entry("big", type: 0o120000, size: 3), linkTarget: target)
        XCTAssertFalse(FileTransferContext.isEditable(link))
    }
}
