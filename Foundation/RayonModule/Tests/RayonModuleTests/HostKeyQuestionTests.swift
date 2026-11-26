//
//  HostKeyQuestionTests.swift
//  RayonModuleTests
//
//  A replaced key is a warning, but for an old release's ECDSA or RSA key
//  giving way to Ed25519.
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
    func testAnOldReleasesKeyGivingWayToEd25519IsAskedAboutCalmly() {
        let question = HostKeyQuestion(host: "example.com", port: 22, offered: ed25519, saved: ecdsa, savedByLegacyRelease: true)
        XCTAssertFalse(question.isWarning)
        XCTAssertEqual(question.title, "Trust example.com?")
        XCTAssertEqual(question.confirmTitle, "Trust and Connect")
        XCTAssertTrue(question.message.contains("ecdsa-sha2-nistp256"), question.message)
        XCTAssertFalse(question.message.contains("intercepting"), question.message)
    }

    /// Saved by this release, a key of another type is as suspect as any.
    func testAKeyOfAnotherTypeIsAWarning() {
        XCTAssertTrue(HostKeyQuestion(host: "example.com", port: 22, offered: ed25519, saved: ecdsa).isWarning)
        XCTAssertTrue(HostKeyQuestion(host: "example.com", port: 22, offered: ecdsa, saved: ed25519, savedByLegacyRelease: true).isWarning)
    }

    func testAReplacedKeyOfTheSameTypeIsAWarning() {
        let question = HostKeyQuestion(host: "example.com", port: 22, offered: otherEd25519, saved: ed25519)
        XCTAssertTrue(question.isWarning)
        XCTAssertTrue(question.title.hasPrefix("WARNING"))
        XCTAssertEqual(question.confirmTitle, "Replace Saved Key")
        XCTAssertTrue(question.message.contains("intercepting"), question.message)
    }
}
