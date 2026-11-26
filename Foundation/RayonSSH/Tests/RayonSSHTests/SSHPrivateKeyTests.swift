//
//  SSHPrivateKeyTests.swift
//  RayonSSHTests
//
//  Reads keys ssh-keygen writes, in every format and type the app takes,
//  and checks the rest fail with a reason a person can act on.
//

import Foundation
@testable import RayonSSH
import XCTest

final class SSHPrivateKeyTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh-keygen") else {
            throw XCTSkip("Needs /usr/bin/ssh-keygen")
        }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func generate(_ arguments: [String], passphrase: String = "") throws -> String {
        let path = folder.appendingPathComponent(UUID().uuidString).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-q", "-N", passphrase, "-f", path] + arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func offers(_ text: String, passphrase: String = "") throws -> Int {
        try SSHPrivateKey(text: text, passphrase: passphrase).offers().count
    }

    func testOpenSSHKeys() throws {
        XCTAssertEqual(try offers(generate(["-t", "ed25519"])), 1)
        for bits in ["256", "384", "521"] {
            XCTAssertEqual(try offers(generate(["-t", "ecdsa", "-b", bits])), 1, bits)
        }
        XCTAssertEqual(try offers(generate(["-t", "rsa", "-b", "2048"])), 3, "rsa-sha2-512, rsa-sha2-256 and ssh-rsa")
    }

    func testEncryptedOpenSSHKeys() throws {
        let ed25519 = try generate(["-t", "ed25519"], passphrase: "secret")
        XCTAssertEqual(try offers(ed25519, passphrase: "secret"), 1)
        XCTAssertThrowsError(try offers(ed25519, passphrase: "wrong")) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not be decrypted"), error.localizedDescription)
        }
        XCTAssertThrowsError(try offers(ed25519)) { error in
            XCTAssertTrue(error.localizedDescription.contains("passphrase"), error.localizedDescription)
        }
        let rsa = try generate(["-t", "rsa", "-b", "2048"], passphrase: "secret")
        XCTAssertEqual(try offers(rsa, passphrase: "secret"), 3, "rsa-sha2-512, rsa-sha2-256 and ssh-rsa")
        for bits in ["256", "384", "521"] {
            let ecdsa = try generate(["-t", "ecdsa", "-b", bits], passphrase: "secret")
            XCTAssertEqual(try offers(ecdsa, passphrase: "secret"), 1, bits)
            XCTAssertThrowsError(try offers(ecdsa, passphrase: "wrong"), bits)
        }
    }

    /// Every cipher `ssh-keygen -Z` can write a key with.
    func testEveryKeyCipher() throws {
        for cipher in ["aes128-ctr", "aes192-ctr", "aes256-ctr", "aes128-cbc", "aes192-cbc", "aes256-cbc", "aes128-gcm@openssh.com", "aes256-gcm@openssh.com"] {
            let key = try generate(["-t", "ecdsa", "-Z", cipher], passphrase: "secret")
            XCTAssertEqual(try offers(key, passphrase: "secret"), 1, cipher)
            XCTAssertThrowsError(try offers(key, passphrase: "wrong"), cipher)
        }
        let chacha = try generate(["-t", "ed25519", "-Z", "chacha20-poly1305@openssh.com"], passphrase: "secret")
        XCTAssertThrowsError(try offers(chacha, passphrase: "secret")) { error in
            XCTAssertTrue(error.localizedDescription.contains("not supported"), error.localizedDescription)
        }
    }

    func testPEMKeys() throws {
        XCTAssertEqual(try offers(generate(["-t", "rsa", "-b", "2048", "-m", "PEM"])), 3)
        XCTAssertEqual(try offers(generate(["-t", "ecdsa", "-m", "PEM"])), 1)
        XCTAssertEqual(try offers(generate(["-t", "rsa", "-b", "2048", "-m", "PKCS8"])), 3)
        let encrypted = try generate(["-t", "rsa", "-b", "2048", "-m", "PEM"], passphrase: "secret")
        XCTAssertEqual(try offers(encrypted, passphrase: "secret"), 3)
        XCTAssertThrowsError(try offers(encrypted, passphrase: "wrong"))
    }

    func testUnsupportedFormatsSayWhy() {
        XCTAssertThrowsError(try offers("PuTTY-User-Key-File-3: ssh-ed25519\n")) { error in
            XCTAssertTrue(error.localizedDescription.contains("PuTTY"))
        }
        XCTAssertThrowsError(try offers("-----BEGIN DSA PRIVATE KEY-----\nAAAA\n-----END DSA PRIVATE KEY-----\n")) { error in
            XCTAssertTrue(error.localizedDescription.contains("DSA"))
        }
        XCTAssertThrowsError(try offers("not a key"))
    }

    func testWhichServersTakeRSASHA2Signatures() {
        XCTAssertTrue(SSHConnection.takesRSASHA2("SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13"))
        XCTAssertTrue(SSHConnection.takesRSASHA2("SSH-2.0-OpenSSH_7.2"))
        XCTAssertTrue(SSHConnection.takesRSASHA2("SSH-2.0-OpenSSH_10.0"))
        XCTAssertFalse(SSHConnection.takesRSASHA2("SSH-2.0-OpenSSH_7.1p2"))
        XCTAssertFalse(SSHConnection.takesRSASHA2("SSH-2.0-dropbear_2022.83"))
        XCTAssertFalse(SSHConnection.takesRSASHA2(nil))
    }

    /// A key whose passphrase takes billions of bcrypt rounds is refused
    /// rather than decrypted forever.
    func testAKeyWithTooManyRoundsIsRefused() throws {
        let text = try generate(["-t", "ed25519"], passphrase: "secret")
        let body = text.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
        var data = try XCTUnwrap(Data(base64Encoded: body))
        // magic, "aes256-ctr", "bcrypt", the options' length, the salt: then the rounds.
        let rounds = 15 + (4 + 10) + (4 + 6) + 4 + (4 + 16)
        data.replaceSubrange(rounds ..< rounds + 4, with: [0xFF, 0xFF, 0xFF, 0xFF])
        let patched = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + data.base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----\n"
        XCTAssertThrowsError(try SSHPrivateKey(text: patched, passphrase: "secret")) { error in
            XCTAssertTrue(error.localizedDescription.contains("rounds"), error.localizedDescription)
        }
    }
}
