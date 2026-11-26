//
//  QuickConnectAliasTests.swift
//  RayonModuleTests
//
//  `ssh myserver` in Quick Connect names a saved server, the way it names
//  a Host in ~/.ssh/config.
//

@testable import RayonModule
import XCTest

@MainActor
final class QuickConnectAliasTests: XCTestCase {
    func testTheAliasIsOneWordWithOrWithoutSSH() {
        XCTAssertEqual(SSHCommandReader.quickConnectAlias("myserver"), "myserver")
        XCTAssertEqual(SSHCommandReader.quickConnectAlias("  ssh myserver "), "myserver")
        XCTAssertEqual(SSHCommandReader.quickConnectAlias("SSH  web.prod"), "web.prod")
        XCTAssertNil(SSHCommandReader.quickConnectAlias(""))
        XCTAssertNil(SSHCommandReader.quickConnectAlias("ssh "))
        XCTAssertNil(SSHCommandReader.quickConnectAlias("SSH"))
        XCTAssertNil(SSHCommandReader.quickConnectAlias("root@myserver"))
        XCTAssertNil(SSHCommandReader.quickConnectAlias("ssh -p 22 myserver"))
        XCTAssertNil(SSHCommandReader.quickConnectAlias("ssh -v"))
        XCTAssertNil(SSHCommandReader.quickConnectAlias("my server"))
    }

    func testAnAliasMatchesANameBeforeAnAddress() throws {
        let test = try TestStorage()
        let store = test.store()
        let tag = UUID().uuidString.prefix(8).lowercased()
        let byName = RDMachine(remoteAddress: "192.0.2.40", remotePort: "22", name: "Web-\(tag)")
        let byAddress = RDMachine(remoteAddress: "host-\(tag).example", remotePort: "2222", name: "Other-\(tag)")
        // Its address spells the first server's name: the name wins.
        let shadow = RDMachine(remoteAddress: "web-\(tag)", remotePort: "22", name: "Shadow-\(tag)")
        for machine in [byName, byAddress, shadow] { store.save(machine) }

        XCTAssertEqual(store.machine(matchingAlias: "web-\(tag)")?.id, byName.id)
        XCTAssertEqual(store.machine(matchingAlias: "WEB-\(tag.uppercased())")?.id, byName.id)
        XCTAssertEqual(store.machine(matchingAlias: "HOST-\(tag).example")?.id, byAddress.id)
        XCTAssertNil(store.machine(matchingAlias: "missing-\(tag)"))
        XCTAssertNil(store.machine(matchingAlias: "  "))

        XCTAssertEqual(store.machine(matchingQuickConnect: "ssh web-\(tag)")?.id, byName.id)
        XCTAssertEqual(store.machine(matchingQuickConnect: "other-\(tag)")?.id, byAddress.id)
        XCTAssertNil(store.machine(matchingQuickConnect: "root@web-\(tag)"))
    }

    func testAUserAtHostStillParsesAsACommand() {
        XCTAssertNotNil(SSHCommandReader(quickConnect: "root@myserver"))
        XCTAssertNil(SSHCommandReader(quickConnect: "myserver"))
    }
}
