//
//  VNCAppleAuth.swift
//  RayonModule
//
//  RFB security type 30, Apple Remote Desktop authentication: what macOS
//  Screen Sharing asks for when it is given a user account rather than a
//  VNC password. The server sends Diffie-Hellman parameters and its public
//  key; the client answers with the user name and password, AES-128-ECB
//  encrypted under MD5 of the shared secret, followed by its own public key.
//

import BigInt
import CommonCrypto
import CryptoKit
import Foundation

enum VNCAppleAuth {
    /// The DH parameters the server opens type 30 with.
    struct ServerParameters {
        var generator: [UInt8]
        var prime: [UInt8]
        var serverPublicKey: [UInt8]

        /// Every big number on the wire is this many bytes, big endian.
        var keyLength: Int { prime.count }
    }

    /// Reads generator(u16) keyLength(u16) prime(keyLength) publicKey(keyLength).
    static func readParameters(from reader: VNCReader) async throws -> ServerParameters {
        let header = try await reader.read(exactly: 4)
        let generator = header.readU16BE(at: 0)
        let keyLength = Int(header.readU16BE(at: 2))
        guard keyLength > 0, keyLength <= 1024 else {
            throw RemoteDesktopFailure(String(localized: "The server sent an unusable Apple authentication key length (\(keyLength)).", bundle: .module))
        }
        let prime = Array(try await reader.read(exactly: keyLength))
        let publicKey = Array(try await reader.read(exactly: keyLength))
        return ServerParameters(
            generator: [UInt8(generator >> 8), UInt8(generator & 0xFF)],
            prime: prime,
            serverPublicKey: publicKey
        )
    }

    /// The client's answer: 128 bytes of encrypted credentials, then the
    /// client public key.
    static func response(
        to parameters: ServerParameters,
        username: String,
        password: String
    ) throws -> Data {
        let length = parameters.keyLength
        let prime = BigUInt(Data(parameters.prime))
        let generator = BigUInt(Data(parameters.generator))
        let serverPublicKey = BigUInt(Data(parameters.serverPublicKey))
        // 0, 1 and p − 1 (and anything out of range) pin the shared secret
        // to a value an attacker knows; a real group element never is one.
        guard prime > 3,
              isValidGroupElement(generator, prime: prime),
              isValidGroupElement(serverPublicKey, prime: prime)
        else {
            throw RemoteDesktopFailure(String(localized: "The server sent unusable Apple authentication key parameters.", bundle: .module))
        }
        // The private exponent lands in [2, p − 2].
        let secret = BigUInt(Data(randomBytes(length))) % (prime - 3) + 2
        let publicKey = generator.power(secret, modulus: prime)
        let shared = serverPublicKey.power(secret, modulus: prime)

        let key = Array(Insecure.MD5.hash(data: bigEndianBytes(shared, length: length)))
        let plain = credentialBlock(username: username, password: password)
        guard let cipher = aes128ECB(plain, key: key) else {
            throw RemoteDesktopFailure(String(localized: "Could not encrypt the Apple authentication credentials.", bundle: .module))
        }
        var data = Data(cipher)
        data.append(bigEndianBytes(publicKey, length: length))
        return data
    }

    /// Whether `value` is a usable DH public value: 1 < value < p − 1.
    static func isValidGroupElement(_ value: BigUInt, prime: BigUInt) -> Bool {
        value > 1 && value < prime - 1
    }

    /// `value` big endian, left-padded with zeros to `length` bytes; the
    /// caller guarantees it fits (it is reduced modulo a `length`-byte prime).
    static func bigEndianBytes(_ value: BigUInt, length: Int) -> Data {
        let bytes = value.serialize()
        return Data(count: max(0, length - bytes.count)) + bytes
    }

    /// 64 bytes of user name and 64 of password, each NUL-terminated and
    /// padded with random bytes, as Apple's client does.
    static func credentialBlock(username: String, password: String) -> [UInt8] {
        func field(_ text: String) -> [UInt8] {
            var bytes = Array(text.utf8.prefix(63))
            bytes.append(0)
            bytes.append(contentsOf: randomBytes(64 - bytes.count))
            return bytes
        }
        return field(username) + field(password)
    }

    static func aes128ECB(_ input: [UInt8], key: [UInt8], decrypt: Bool = false) -> [UInt8]? {
        guard key.count == kCCKeySizeAES128, input.count % kCCBlockSizeAES128 == 0 else { return nil }
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let status = CCCrypt(
            CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            input, input.count,
            &output, output.count,
            &moved
        )
        guard status == kCCSuccess, moved == input.count else { return nil }
        return output
    }

    static func randomBytes(_ count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for index in bytes.indices { bytes[index] = .random(in: .min ... .max) }
        }
        return bytes
    }
}
