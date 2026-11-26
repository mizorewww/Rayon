//
//  HostKeyQuestionTests.swift
//  RayonModuleTests
//
//  Only a replaced key of the same type is asked about as a warning.
//

@testable import RayonModule
import RayonSSH
import XCTest

final class HostKeyQuestionTests: XCTestCase {
    private let ed25519 = SSHHostKey(type: "ssh-ed25519", key: Data([1]))
    private let otherEd25519 = SSHHostKey(type: "ssh-ed25519", key: Data([2]))
    private let ecdsa = SSHHostKey(type: "ecdsa-sha2-nistp256", key: Data([3]))

    func testAFirstKeyIsAskedAboutCalmly() {
        let question = HostKeyQuestion(host: "example.com", port: 22, offered: ed25519, saved: nil)
        XCTAssertFalse(question.isWarning)
        XCTAssertEqual(question.confirmTitle, "Trust and Connect")
    }

    /// A server saved by the libssh2 build (ECDSA) presenting Ed25519 now.
    func testAKeyOfAnotherTypeIsAskedAboutCalmly() {
        let question = HostKeyQuestion(host: "example.com", port: 22, offered: ed25519, saved: ecdsa)
        XCTAssertFalse(question.isWarning)
        XCTAssertEqual(question.title, "Trust example.com?")
        XCTAssertEqual(question.confirmTitle, "Trust and Connect")
        XCTAssertTrue(question.message.contains("ecdsa-sha2-nistp256"), question.message)
        XCTAssertFalse(question.message.contains("intercepting"), question.message)
    }

    func testAReplacedKeyOfTheSameTypeIsAWarning() {
        let question = HostKeyQuestion(host: "example.com", port: 22, offered: otherEd25519, saved: ed25519)
        XCTAssertTrue(question.isWarning)
        XCTAssertTrue(question.title.hasPrefix("WARNING"))
        XCTAssertEqual(question.confirmTitle, "Replace Saved Key")
        XCTAssertTrue(question.message.contains("intercepting"), question.message)
    }
}
