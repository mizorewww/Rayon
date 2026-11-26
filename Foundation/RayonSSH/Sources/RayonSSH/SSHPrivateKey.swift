//
//  SSHPrivateKey.swift
//  RayonSSH
//
//  Reads the private keys people paste: OpenSSH's own format (Ed25519,
//  ECDSA, RSA, plain or passphrase-protected) and PEM (PKCS#1, SEC1,
//  PKCS#8, including the legacy OpenSSL encryption `ssh-keygen -m PEM`
//  writes). What cannot be read says why.
//

import _CryptoExtras
import Citadel
import CommonCrypto
import Crypto
import Foundation
import NIOCore
import NIOSSH

public struct SSHPrivateKey: Sendable {
    enum Storage: Sendable {
        case ed25519(Curve25519.Signing.PrivateKey)
        case p256(P256.Signing.PrivateKey)
        case p384(P384.Signing.PrivateKey)
        case p521(P521.Signing.PrivateKey)
        case rsa(_RSA.Signing.PrivateKey)
    }

    let storage: Storage

    public init(text: String, passphrase: String? = nil) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let passphrase = passphrase.flatMap { $0.isEmpty ? nil : $0 }
        if text.contains("BEGIN OPENSSH PRIVATE KEY") {
            storage = try Self.readOpenSSH(text, passphrase: passphrase)
        } else if text.contains("-----BEGIN") {
            storage = try Self.readPEM(text, passphrase: passphrase)
        } else if text.hasPrefix("PuTTY-User-Key-File") {
            throw SSHError.unsupportedKey("PuTTY keys (.ppk) are not supported. Export the key in OpenSSH format from PuTTYgen.")
        } else {
            throw SSHError.unsupportedKey("This does not look like a private key.")
        }
    }

    /// What the key signs with, most preferred first.
    func offers() throws -> [NIOSSHPrivateKey] {
        switch storage {
        case let .ed25519(key): return [NIOSSHPrivateKey(ed25519Key: key)]
        case let .p256(key): return [NIOSSHPrivateKey(p256Key: key)]
        case let .p384(key): return [NIOSSHPrivateKey(p384Key: key)]
        case let .p521(key): return [NIOSSHPrivateKey(p521Key: key)]
        case let .rsa(key):
            return [
                NIOSSHPrivateKey(custom: RSAUserKey<RSASHA512>(key)),
                NIOSSHPrivateKey(custom: RSAUserKey<RSASHA256>(key)),
                NIOSSHPrivateKey(custom: RSAUserKey<RSASHA1>(key)),
            ]
        }
    }

    // MARK: OpenSSH

    private static func readOpenSSH(_ text: String, passphrase: String?) throws -> Storage {
        let body = text
            .replacingOccurrences(of: "-----BEGIN OPENSSH PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END OPENSSH PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: body) else { throw malformed }
        var buffer = ByteBuffer(data: data)
        let magic = Array("openssh-key-v1\0".utf8)
        guard buffer.readBytes(length: magic.count) == magic,
              let cipher = buffer.readSSHText(),
              let kdf = buffer.readSSHText(),
              var kdfOptions = buffer.readLengthPrefixedSlice(as: UInt32.self),
              buffer.readInteger(as: UInt32.self) == 1,
              var publicKey = buffer.readLengthPrefixedSlice(as: UInt32.self),
              let type = publicKey.readSSHText(),
              var section = buffer.readLengthPrefixedSlice(as: UInt32.self)
        else { throw malformed }

        if cipher != "none" {
            guard let passphrase else {
                throw SSHError.unsupportedKey("The private key is protected by a passphrase. Enter it as the identity's password.")
            }
            guard kdf == "bcrypt",
                  let salt = kdfOptions.readLengthPrefixedSlice(as: UInt32.self),
                  let rounds = kdfOptions.readInteger(as: UInt32.self)
            else { throw SSHError.unsupportedKey("The key is encrypted with an unknown key derivation (\(kdf)).") }
            let tag = buffer.readBytes(length: buffer.readableBytes) ?? []
            let plain = try OpenSSHKeyCipher.decrypt(
                Array(section.readableBytesView), tag: tag, cipher: cipher,
                passphrase: Array(passphrase.utf8), salt: Array(salt.readableBytesView), rounds: rounds
            )
            section = ByteBuffer(bytes: plain)
        }

        // The check integers match only when the passphrase was right.
        guard let check1 = section.readInteger(as: UInt32.self),
              let check2 = section.readInteger(as: UInt32.self)
        else { throw malformed }
        guard check1 == check2 else {
            throw SSHError.unsupportedKey("The private key could not be decrypted. Check the identity's password, which is the key's passphrase.")
        }
        guard section.readSSHText() == type else { throw malformed }
        switch type {
        case "ssh-ed25519":
            guard section.readLengthPrefixedSlice(as: UInt32.self) != nil,
                  let secret = section.readLengthPrefixedSlice(as: UInt32.self), secret.readableBytes == 64
            else { throw malformed }
            return try .ed25519(Curve25519.Signing.PrivateKey(rawRepresentation: secret.getBytes(at: secret.readerIndex, length: 32)!))
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            guard section.readSSHText() != nil, // curve
                  section.readLengthPrefixedSlice(as: UInt32.self) != nil, // Q
                  let scalar = section.readMPIntMagnitude()
            else { throw malformed }
            switch type {
            case "ecdsa-sha2-nistp256": return try .p256(P256.Signing.PrivateKey(rawRepresentation: scalar.leftPadded(to: 32)))
            case "ecdsa-sha2-nistp384": return try .p384(P384.Signing.PrivateKey(rawRepresentation: scalar.leftPadded(to: 48)))
            default: return try .p521(P521.Signing.PrivateKey(rawRepresentation: scalar.leftPadded(to: 66)))
            }
        case "ssh-rsa":
            guard let n = section.readMPIntMagnitude(),
                  let e = section.readMPIntMagnitude(),
                  let d = section.readMPIntMagnitude(),
                  section.readMPIntMagnitude() != nil, // iqmp
                  let p = section.readMPIntMagnitude(),
                  let q = section.readMPIntMagnitude()
            else { throw malformed }
            return try .rsa(_RSA.Signing.PrivateKey(n: n, e: e, d: d, p: p, q: q))
        default:
            throw SSHError.unsupportedKey("\(type) keys are not supported. Use an Ed25519, ECDSA or RSA key.")
        }
    }

    // MARK: PEM

    private static func readPEM(_ text: String, passphrase: String?) throws -> Storage {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let begin = lines.first(where: { $0.hasPrefix("-----BEGIN ") }) else { throw malformed }
        let label = begin.dropFirst("-----BEGIN ".count).prefix { $0 != "-" }
        var headers: [String: String] = [:]
        var body = ""
        for line in lines where !line.hasPrefix("-----") && !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                headers[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            } else {
                body += line
            }
        }
        guard var der = Data(base64Encoded: body) else { throw malformed }
        if headers["Proc-Type"]?.hasSuffix("ENCRYPTED") == true {
            guard let passphrase else {
                throw SSHError.unsupportedKey("The private key is protected by a passphrase. Enter it as the identity's password.")
            }
            der = try decryptLegacyPEM(der, info: headers["DEK-Info"] ?? "", passphrase: passphrase)
        }
        switch label {
        case "RSA PRIVATE KEY":
            return try .rsa(readRSA(der))
        case "EC PRIVATE KEY", "PRIVATE KEY":
            if let key = try? _RSA.Signing.PrivateKey(unsafeDERRepresentation: der) { return .rsa(key) }
            if let key = try? P256.Signing.PrivateKey(derRepresentation: der) { return .p256(key) }
            if let key = try? P384.Signing.PrivateKey(derRepresentation: der) { return .p384(key) }
            if let key = try? P521.Signing.PrivateKey(derRepresentation: der) { return .p521(key) }
            // CryptoKit turns down the SEC1 keys ssh-keygen writes; their
            // scalar is all a signing key needs.
            if let scalar = Self.sec1Scalar(der) {
                if let key = try? P256.Signing.PrivateKey(rawRepresentation: scalar) { return .p256(key) }
                if let key = try? P384.Signing.PrivateKey(rawRepresentation: scalar) { return .p384(key) }
                if let key = try? P521.Signing.PrivateKey(rawRepresentation: scalar) { return .p521(key) }
            }
            throw SSHError.unsupportedKey("The PEM key could not be read. Rayon reads RSA and ECDSA keys in PEM.")
        case "ENCRYPTED PRIVATE KEY":
            throw SSHError.unsupportedKey("Encrypted PKCS#8 keys are not supported. Convert the key with `ssh-keygen -p -f <key>`, which writes OpenSSH format.")
        case "DSA PRIVATE KEY":
            throw SSHError.unsupportedKey("DSA keys are not supported. Use an Ed25519, ECDSA or RSA key.")
        default:
            throw SSHError.unsupportedKey("\"\(label)\" is not a private key Rayon can read.")
        }
    }

    private static func readRSA(_ der: Data) throws -> _RSA.Signing.PrivateKey {
        do {
            return try _RSA.Signing.PrivateKey(unsafeDERRepresentation: der)
        } catch {
            throw malformed
        }
    }

    /// OpenSSL's `Proc-Type: 4,ENCRYPTED` PEM: the key and IV come from
    /// MD5 over the passphrase and the IV's first 8 bytes (EVP_BytesToKey).
    private static func decryptLegacyPEM(_ data: Data, info: String, passphrase: String) throws -> Data {
        let parts = info.split(separator: ",").map(String.init)
        guard parts.count == 2, let iv = Data(hex: parts[1]) else { throw malformed }
        let algorithm: CCAlgorithm
        let keyLength: Int
        switch parts[0] {
        case "AES-128-CBC": (algorithm, keyLength) = (CCAlgorithm(kCCAlgorithmAES), kCCKeySizeAES128)
        case "AES-192-CBC": (algorithm, keyLength) = (CCAlgorithm(kCCAlgorithmAES), kCCKeySizeAES192)
        case "AES-256-CBC": (algorithm, keyLength) = (CCAlgorithm(kCCAlgorithmAES), kCCKeySizeAES256)
        case "DES-EDE3-CBC": (algorithm, keyLength) = (CCAlgorithm(kCCAlgorithm3DES), kCCKeySize3DES)
        default: throw SSHError.unsupportedKey("PEM keys encrypted with \(parts[0]) are not supported.")
        }
        var key = Data()
        var block = Data()
        while key.count < keyLength {
            block = Data(Insecure.MD5.hash(data: block + Data(passphrase.utf8) + iv.prefix(8)))
            key += block
        }
        key = key.prefix(keyLength)
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var written = 0
        let outputCount = output.count
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(
                            CCOperation(kCCDecrypt), algorithm, CCOptions(kCCOptionPKCS7Padding),
                            key.baseAddress, keyLength, iv.baseAddress,
                            input.baseAddress, input.count,
                            out.baseAddress, outputCount, &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw SSHError.unsupportedKey("The private key could not be decrypted. Check the identity's password, which is the key's passphrase.")
        }
        return output.prefix(written)
    }

    /// The private scalar of a SEC1 ECPrivateKey:
    /// SEQUENCE { INTEGER 1, OCTET STRING scalar, ... }.
    private static func sec1Scalar(_ der: Data) -> Data? {
        var bytes = der[...]
        func element(_ tag: UInt8) -> Data? {
            guard bytes.first == tag else { return nil }
            bytes = bytes.dropFirst()
            guard let first = bytes.first else { return nil }
            bytes = bytes.dropFirst()
            var length = Int(first)
            if first & 0x80 != 0 {
                let count = Int(first & 0x7F)
                guard count <= 3, bytes.count >= count else { return nil }
                length = bytes.prefix(count).reduce(0) { $0 << 8 | Int($1) }
                bytes = bytes.dropFirst(count)
            }
            guard bytes.count >= length else { return nil }
            defer { bytes = bytes.dropFirst(length) }
            return Data(bytes.prefix(length))
        }
        guard let sequence = element(0x30) else { return nil }
        bytes = sequence[...]
        guard element(0x02) == Data([1]) else { return nil }
        return element(0x04)
    }

    private static let malformed = SSHError.unsupportedKey("The private key is damaged or incomplete.")
}

extension ByteBuffer {
    mutating func readSSHText() -> String? {
        readLengthPrefixedSlice(as: UInt32.self).map { String(buffer: $0) }
    }

    mutating func readMPIntMagnitude() -> Data? {
        readLengthPrefixedSlice(as: UInt32.self).map { Data($0.readableBytesView.drop(while: { $0 == 0 })) }
    }
}

private extension Data {
    func leftPadded(to size: Int) -> Data {
        count >= size ? suffix(size) : Data(repeating: 0, count: size - count) + self
    }

    init?(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
