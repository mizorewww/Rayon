//
//  RemoteFileComparatorTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import RayonSSH
import UniformTypeIdentifiers
import XCTest

final class RemoteFileComparatorTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/srv")

    private func file(_ name: String, size: Int64 = 0, days: Double = 0, folder: Bool = false) -> FileTransferContext.RemoteFile {
        let entry = SFTPEntry(
            name: name,
            size: size,
            permissions: (folder ? 0o040000 : 0o100000) | 0o644,
            modificationDate: Date(timeIntervalSince1970: days * 86400)
        )
        return FileTransferContext.RemoteFile(base: base, name: name, fstat: entry)
    }

    private lazy var files = [
        file("b.txt", size: 30, days: 1),
        file("a10.log", size: 10, days: 3),
        file("logs", folder: true),
        file("a9.gz", size: 20, days: 2),
        file("etc", folder: true),
    ]

    func testNamesSortAsFinderDoesWithFoldersOnTop() {
        XCTAssertEqual(files.sorted(using: RemoteFileComparator(.name)).map(\.name), ["etc", "logs", "a9.gz", "a10.log", "b.txt"])
    }

    func testAReversedColumnKeepsFoldersOnTop() {
        XCTAssertEqual(files.sorted(using: RemoteFileComparator(.name, order: .reverse)).map(\.name), ["logs", "etc", "b.txt", "a10.log", "a9.gz"])
    }

    func testSizeAndDateSortTheirValues() {
        XCTAssertEqual(files.sorted(using: RemoteFileComparator(.size)).map(\.name), ["etc", "logs", "a10.log", "a9.gz", "b.txt"])
        XCTAssertEqual(files.sorted(using: RemoteFileComparator(.modified, order: .reverse)).map(\.name), ["logs", "etc", "a10.log", "a9.gz", "b.txt"])
    }

    func testKindGroupsFilesOfOneKind() {
        let sorted = files.sorted(using: RemoteFileComparator(.kind)).filter { !$0.isFolder }
        XCTAssertEqual(sorted.map(\.kind), sorted.map(\.kind).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(file("logs", folder: true).kind.lowercased(), UTType.folder.localizedDescription?.lowercased())
        XCTAssertEqual(file("logs", folder: true).kind.first?.isUppercase, true)
    }

    func testAFileIsKnownByItsPath() {
        XCTAssertEqual(file("b.txt").id, URL(fileURLWithPath: "/srv/b.txt"))
        XCTAssertEqual(file("b.txt", size: 1).id, file("b.txt", size: 2).id)
    }

    func testADownloadTakesAFreeName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = URL(fileURLWithPath: "/srv/notes.txt")
        XCTAssertEqual(FileTransferContext.freeDestination(for: item, in: folder).lastPathComponent, "notes.txt")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("notes.txt").path, contents: nil)
        XCTAssertEqual(FileTransferContext.freeDestination(for: item, in: folder).lastPathComponent, "notes.2.txt")
    }
}
