@testable import RayonModule
import XCTest

final class KnownHostsTests: XCTestCase {
    private var test: TestStorage!
    private var hosts: KnownHosts!

    private let first = KnownHosts.HostKey(type: "ssh-ed25519", key: Data([1, 2, 3, 4]))
    private let other = KnownHosts.HostKey(type: "ssh-ed25519", key: Data([9, 9, 9, 9]))

    override func setUpWithError() throws {
        test = try TestStorage()
        hosts = KnownHosts(storage: test.storage)
    }

    override func tearDown() {
        hosts = nil
        test = nil
    }

    func testTheFirstKeyIsSavedAndAcceptedAgain() {
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        XCTAssertEqual(hosts.savedKey(host: "example.com", port: 22), first)
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        XCTAssertNil(hosts.refusalMessage(host: "example.com", port: 22))
    }

    func testAChangedKeyIsRefusedAndTheSavedOneKept() {
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        XCTAssertFalse(hosts.accepts(other, host: "example.com", port: 22))
        XCTAssertEqual(hosts.savedKey(host: "example.com", port: 22), first)
        XCTAssertEqual(hosts.refusedKey(host: "example.com", port: 22), other)
        let message = hosts.refusalMessage(host: "example.com", port: 22)
        XCTAssertTrue(message?.contains(first.fingerprint) == true)
        XCTAssertTrue(message?.contains(other.fingerprint) == true)
    }

    func testTheSameKeyOfAnotherTypeIsRefused() {
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        let retyped = KnownHosts.HostKey(type: "ssh-rsa", key: first.key)
        XCTAssertFalse(hosts.accepts(retyped, host: "example.com", port: 22))
    }

    func testAKeyIsSavedPerAddressAndPort() {
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        XCTAssertTrue(hosts.accepts(other, host: "example.com", port: 2222))
        XCTAssertTrue(hosts.accepts(other, host: "other.example.com", port: 22))
        XCTAssertTrue(hosts.accepts(first, host: " Example.COM ", port: 22), "an address is the same in any case")
        XCTAssertEqual(hosts.count, 3)
    }

    func testForgettingLetsTheNextKeyIn() {
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        XCTAssertFalse(hosts.accepts(other, host: "example.com", port: 22))
        hosts.forget(host: "example.com", port: 22)
        XCTAssertNil(hosts.refusalMessage(host: "example.com", port: 22))
        XCTAssertTrue(hosts.accepts(other, host: "example.com", port: 22))
        XCTAssertEqual(hosts.savedKey(host: "example.com", port: 22), other)
    }

    func testSavedKeysOutliveTheObject() {
        XCTAssertTrue(hosts.accepts(first, host: "example.com", port: 22))
        let reopened = KnownHosts(storage: test.storage)
        XCTAssertFalse(reopened.accepts(other, host: "example.com", port: 22))
        reopened.forgetAll()
        XCTAssertEqual(reopened.count, 0)
    }

    func testTheFingerprintIsTheOneSSHPrints() {
        // SHA-256 of an empty key, base64 without padding.
        let empty = KnownHosts.HostKey(type: "ssh-ed25519", key: Data())
        XCTAssertEqual(empty.fingerprint, "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU")
    }
}
