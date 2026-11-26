//
//  FolderTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

@MainActor
final class FolderTests: XCTestCase {
    private var test: TestStorage!
    private var store: RayonStore!

    override func setUp() async throws {
        test = try TestStorage()
        store = test.store()
    }

    override func tearDown() async throws {
        store = nil
        test = nil
    }

    private func server(_ name: String, folder: RDFolder? = nil) -> RDMachine {
        let machine = RDMachine(remoteAddress: "\(name).example", remotePort: "22", name: name, folderId: folder?.id)
        store.save(machine)
        return machine
    }

    func testFoldersAreSortedAndEmptyFoldersStay() {
        let prod = store.createFolder(named: "prod")
        _ = server("a", folder: prod)
        store.createFolder(named: "empty")
        XCTAssertEqual(store.folders.map(\.name), ["empty", "prod"])
    }

    func testNewFolderNamesAreUnique() {
        store.createFolder(named: "lab")
        XCTAssertEqual(store.createFolder(named: "lab").name, "lab 2")
        XCTAssertEqual(store.createFolder(named: "  ").name, "New Folder")
    }

    /// Servers name their folder by id: a rename leaves them where they are.
    func testRenameKeepsServersAndRefusesTakenNames() {
        let prod = store.createFolder(named: "prod")
        store.createFolder(named: "lab")
        let a = server("a", folder: prod)
        XCTAssertFalse(store.renameFolder(prod.id, to: "lab"))
        XCTAssertTrue(store.renameFolder(prod.id, to: "production"))
        XCTAssertEqual(store.folderName(of: store.machine(a.id)!), "production")
        XCTAssertNil(store.folder(named: "prod"))
    }

    func testDeletingALocalFolderKeepsItsServers() {
        let prod = store.createFolder(named: "prod")
        let a = server("a", folder: prod)
        store.deleteFolder(prod.id)
        XCTAssertNil(store.machine(a.id)?.folderId)
        XCTAssertNotNil(store.machine(a.id))
        XCTAssertTrue(store.folders.isEmpty)
    }

    func testDeletingALinkedFolderRemovesOnlyPulledServers() {
        let folder = store.createFolder(named: "UU Remote", source: .uuRemote(userID: "u1"))
        let handMade = server("a", folder: folder)
        var device = UUDeviceInfo()
        device.deviceID = "d1"
        device.platform = 4
        let pulled = UURemoteFolderSync.makeMachine(for: device, folder: folder.id)
        store.save(pulled)
        store.deleteFolder(folder.id)
        XCTAssertNil(store.machine(pulled.id))
        XCTAssertNotNil(store.machine(handMade.id))
        XCTAssertNil(store.machine(handMade.id)?.folderId)
    }

    func testFoldersOutliveTheStore() {
        let folder = store.createFolder(named: "b", source: .uuRemote(userID: "42"))
        let reopened = test.store()
        XCTAssertEqual(reopened.folders, [folder])
    }
}
