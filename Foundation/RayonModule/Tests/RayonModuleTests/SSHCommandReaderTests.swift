//
//  SSHCommandReaderTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class SSHCommandReaderTests: XCTestCase {
    func testBasicCommand() {
        let reader = SSHCommandReader(command: "ssh root@example.com")
        XCTAssertEqual(reader?.username, "root")
        XCTAssertEqual(reader?.remoteAddress, "example.com")
        XCTAssertEqual(reader?.remotePort, "22")
    }

    func testCustomPort() {
        let reader = SSHCommandReader(command: "ssh ubuntu@10.0.0.8 -p 2222")
        XCTAssertEqual(reader?.remotePort, "2222")
        XCTAssertEqual(reader?.command, "ssh ubuntu@10.0.0.8 -p 2222")
    }

    func testRejectsAnonymousLogin() {
        XCTAssertNil(SSHCommandReader(command: "ssh example.com"))
    }

    func testRejectsMissingParts() {
        XCTAssertNil(SSHCommandReader(command: "ssh @example.com"))
        XCTAssertNil(SSHCommandReader(command: "ssh root@"))
        XCTAssertNil(SSHCommandReader(command: "ssh"))
        XCTAssertNil(SSHCommandReader(command: "mosh root@example.com"))
    }

    func testRejectsInvalidPort() {
        XCTAssertNil(SSHCommandReader(command: "ssh root@example.com -p abc"))
        XCTAssertNil(SSHCommandReader(command: "ssh root@example.com -p 70000"))
    }

    func testToleratesRepeatedSpaces() {
        let reader = SSHCommandReader(command: "ssh  root@example.com  -p  2222")
        XCTAssertEqual(reader?.username, "root")
        XCTAssertEqual(reader?.remotePort, "2222")
    }

    func testRoundTrip() {
        let original = "ssh deploy@192.168.1.10 -p 2200"
        let reader = SSHCommandReader(command: original)
        XCTAssertEqual(reader?.command, original)
    }
}
