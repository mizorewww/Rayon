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

    /// A server that suddenly presents a key of another type is as
    /// suspect as one presenting another key of the same type.
    func testAKeyOfAnotherTypeIsAWarning() {
        hosts.trust(first, host: "example.com", port: 22)
        let ecdsa = KnownHosts.HostKey(type: "ecdsa-sha2-nistp256", key: Data([5]))
        XCTAssertTrue(hosts.question(offering: ecdsa, host: "example.com", port: 22).isWarning)
        XCTAssertTrue(hosts.question(offering: other, host: "example.com", port: 22).isWarning)
        XCTAssertFalse(hosts.question(offering: first, host: "new.example.com", port: 22).isWarning)
    }

    /// The one calm change: the ECDSA or RSA key libssh2 saw gives way to
    /// the Ed25519 key asked for now, once.
    func testAKeyAnOldReleaseSavedGivesWayToEd25519Once() throws {
        let ecdsa = KnownHosts.HostKey(type: "ecdsa-sha2-nistp256", key: Data([5]))
        let rsa = KnownHosts.HostKey(type: "ssh-rsa", key: Data([6]))
        let name = KnownHosts.name(host: "example.com", port: 22)
        try test.storage.saveKnownHost(KnownHostRecord(name: name, type: ecdsa.type, key: ecdsa.key, legacy: true))
        XCTAssertFalse(hosts.question(offering: first, host: "example.com", port: 22).isWarning)
        XCTAssertTrue(hosts.question(offering: rsa, host: "example.com", port: 22).isWarning, "only Ed25519 is preferred now")
        try test.storage.saveKnownHost(KnownHostRecord(name: name, type: first.type, key: first.key, legacy: true))
        XCTAssertTrue(hosts.question(offering: ecdsa, host: "example.com", port: 22).isWarning, "Ed25519 was never libssh2's choice over ECDSA")

        try test.storage.saveKnownHost(KnownHostRecord(name: name, type: rsa.type, key: rsa.key, legacy: true))
        XCTAssertFalse(hosts.question(offering: first, host: "example.com", port: 22).isWarning)
        hosts.trust(first, host: "example.com", port: 22)
        XCTAssertEqual(test.storage.knownHost(named: name)?.legacy, false)
        XCTAssertTrue(hosts.question(offering: rsa, host: "example.com", port: 22).isWarning, "trusted again, the key is this release's")
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
