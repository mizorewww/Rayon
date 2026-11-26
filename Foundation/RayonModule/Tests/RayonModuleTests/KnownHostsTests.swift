@testable import RayonModule
import RayonSSH
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

    func testAnUnknownKeyIsNotTrustedUntilAsked() {
        XCTAssertEqual(hosts.status(of: first, host: "example.com", port: 22), .unknown)
        XCTAssertNil(hosts.savedKey(host: "example.com", port: 22), "looking a key up does not save it")
        hosts.trust(first, host: "example.com", port: 22)
        XCTAssertEqual(hosts.status(of: first, host: "example.com", port: 22), .trusted)
    }

    func testAChangedKeyIsReportedWithTheSavedOne() {
        hosts.trust(first, host: "example.com", port: 22)
        XCTAssertEqual(hosts.status(of: other, host: "example.com", port: 22), .changed(saved: first))
        XCTAssertEqual(hosts.savedKey(host: "example.com", port: 22), first)
    }

    func testTheSameKeyOfAnotherTypeIsAChange() {
        hosts.trust(first, host: "example.com", port: 22)
        let retyped = KnownHosts.HostKey(type: "ssh-rsa", key: first.key)
        XCTAssertEqual(hosts.status(of: retyped, host: "example.com", port: 22), .changed(saved: first))
    }

    func testAKeyIsSavedPerAddressAndPort() {
        hosts.trust(first, host: "example.com", port: 22)
        XCTAssertEqual(hosts.status(of: first, host: "example.com", port: 2222), .unknown)
        XCTAssertEqual(hosts.status(of: first, host: "other.example.com", port: 22), .unknown)
        XCTAssertEqual(hosts.status(of: first, host: " Example.COM ", port: 22), .trusted, "an address is the same in any case")
        XCTAssertEqual(hosts.count, 1)
    }

    func testForgettingAsksAgain() {
        hosts.trust(first, host: "example.com", port: 22)
        hosts.forget(host: "example.com", port: 22)
        XCTAssertEqual(hosts.status(of: first, host: "example.com", port: 22), .unknown)
    }

    func testSavedKeysOutliveTheObject() {
        hosts.trust(first, host: "example.com", port: 22)
        let reopened = KnownHosts(storage: test.storage)
        XCTAssertEqual(reopened.status(of: other, host: "example.com", port: 22), .changed(saved: first))
        reopened.forgetAll()
        XCTAssertEqual(reopened.count, 0)
    }

    func testTheFingerprintIsTheOneSSHPrints() {
        // SHA-256 of an empty key, base64 without padding.
        let empty = KnownHosts.HostKey(type: "ssh-ed25519", key: Data())
        XCTAssertEqual(empty.fingerprint, "SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU")
    }

    /// Connecting falls back to port 22, so forgetting must too.
    func testForgettingTheKeyOfAServerWithNoPort() {
        var machine = RDMachine()
        machine.remoteAddress = "example.com"
        machine.remotePort = ""
        hosts.trust(first, host: "example.com", port: machine.sshPort)
        machine.forgetHostKey(in: hosts)
        XCTAssertNil(hosts.savedKey(host: "example.com", port: 22))
    }
}
