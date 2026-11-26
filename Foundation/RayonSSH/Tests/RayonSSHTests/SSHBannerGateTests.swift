@testable import RayonSSH
import XCTest

final class SSHBannerGateTests: XCTestCase {
    /// The identification line ends at its CRLF; the key exchange that
    /// follows in the same read is not part of it.
    func testTheIdentificationStopsAtItsLineEnd() {
        let head = "SSH-2.0-OpenSSH_9.7\r\n\u{0}\u{0}\u{4}\u{c}\u{a}\u{14}curve25519-sha256,ecdh-sha2-nistp256\n"
        XCTAssertEqual(SSHBannerGate.identification(in: head), "SSH-2.0-OpenSSH_9.7")
    }

    /// Lines the server sends before its identification are passed over,
    /// and a line not finished yet is not taken.
    func testOnlyAFinishedIdentificationLineCounts() {
        XCTAssertEqual(SSHBannerGate.identification(in: "Welcome\r\nSSH-2.0-dropbear\r\n"), "SSH-2.0-dropbear")
        XCTAssertNil(SSHBannerGate.identification(in: "SSH-2.0-OpenSSH_9.7"))
    }
}
