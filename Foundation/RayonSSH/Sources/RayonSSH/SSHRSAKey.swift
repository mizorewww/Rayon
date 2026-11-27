//
//  SSHRSAKey.swift
//  RayonSSH
//
//  RSA user keys signing with rsa-sha2-512, rsa-sha2-256 (RFC 8332) or the
//  legacy ssh-rsa. swift-nio-ssh names a custom key, its blob and its
//  signature with one prefix, so the rsa-sha2 keys go out with the
//  algorithm name as the blob's type; OpenSSH resolves that name to an RSA
//  key, and every other server gets the ssh-rsa offer after it.
//

import _CryptoExtras
import Crypto
import Foundation
import NIOCore
import NIOSSH

protocol RSASignatureAlgorithm: Sendable {
    static var name: String { get }
    static func sign(_ data: some DataProtocol, with key: _RSA.Signing.PrivateKey) throws -> Data
    static func verify(_ signature: Data, for data: some DataProtocol, with key: _RSA.Signing.PublicKey) -> Bool
}

enum RSASHA512: RSASignatureAlgorithm {
    static let name = "rsa-sha2-512"
    static func sign(_ data: some DataProtocol, with key: _RSA.Signing.PrivateKey) throws -> Data {
        try key.signature(for: SHA512.hash(data: data), padding: .insecurePKCS1v1_5).rawRepresentation
    }

    static func verify(_ signature: Data, for data: some DataProtocol, with key: _RSA.Signing.PublicKey) -> Bool {
        key.isValidSignature(.init(rawRepresentation: signature), for: SHA512.hash(data: data), padding: .insecurePKCS1v1_5)
    }
}

enum RSASHA256: RSASignatureAlgorithm {
    static let name = "rsa-sha2-256"
    static func sign(_ data: some DataProtocol, with key: _RSA.Signing.PrivateKey) throws -> Data {
        try key.signature(for: SHA256.hash(data: data), padding: .insecurePKCS1v1_5).rawRepresentation
    }

    static func verify(_ signature: Data, for data: some DataProtocol, with key: _RSA.Signing.PublicKey) -> Bool {
        key.isValidSignature(.init(rawRepresentation: signature), for: SHA256.hash(data: data), padding: .insecurePKCS1v1_5)
    }
}

enum RSASHA1: RSASignatureAlgorithm {
    static let name = "ssh-rsa"
    static func sign(_ data: some DataProtocol, with key: _RSA.Signing.PrivateKey) throws -> Data {
        try key.signature(for: Insecure.SHA1.hash(data: data), padding: .insecurePKCS1v1_5).rawRepresentation
    }

    static func verify(_ signature: Data, for data: some DataProtocol, with key: _RSA.Signing.PublicKey) -> Bool {
        key.isValidSignature(.init(rawRepresentation: signature), for: Insecure.SHA1.hash(data: data), padding: .insecurePKCS1v1_5)
    }
}

final class RSAUserKey<Algorithm: RSASignatureAlgorithm>: NIOSSHPrivateKeyProtocol, Sendable {
    static var keyPrefix: String { Algorithm.name }

    let key: _RSA.Signing.PrivateKey

    init(_ key: _RSA.Signing.PrivateKey) {
        self.key = key
    }

    var publicKey: NIOSSHPublicKeyProtocol {
        RSAUserPublicKey<Algorithm>(key.publicKey)
    }

    func signature<D: DataProtocol>(for data: D) throws -> NIOSSHSignatureProtocol {
        try RSAUserSignature<Algorithm>(rawRepresentation: Algorithm.sign(data, with: key))
    }
}

final class RSAUserPublicKey<Algorithm: RSASignatureAlgorithm>: NIOSSHPublicKeyProtocol, Sendable {
    static var publicKeyPrefix: String { Algorithm.name }

    let key: _RSA.Signing.PublicKey

    init(_ key: _RSA.Signing.PublicKey) {
        self.key = key
    }

    var rawRepresentation: Data {
        var buffer = ByteBuffer()
        _ = write(to: &buffer)
        return Data(buffer.readableBytesView)
    }

    func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        guard let signature = signature as? RSAUserSignature<Algorithm> else { return false }
        return Algorithm.verify(signature.rawRepresentation, for: data, with: key)
    }

    /// e, then n, as mpints.
    func write(to buffer: inout ByteBuffer) -> Int {
        guard let primitives = try? key.getKeyPrimitives() else { return 0 }
        return buffer.writeSSHMPInt(primitives.publicExponent) + buffer.writeSSHMPInt(primitives.modulus)
    }

    static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let e = buffer.readLengthPrefixedSlice(as: UInt32.self),
              let n = buffer.readLengthPrefixedSlice(as: UInt32.self)
        else { throw SSHError.unsupportedKey(String(localized: "Malformed RSA public key.", bundle: .module)) }
        return try Self(_RSA.Signing.PublicKey(n: Data(n.readableBytesView), e: Data(e.readableBytesView)))
    }
}

struct RSAUserSignature<Algorithm: RSASignatureAlgorithm>: NIOSSHSignatureProtocol, Sendable {
    static var signaturePrefix: String { Algorithm.name }

    let rawRepresentation: Data

    func write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeSSHBytes(rawRepresentation)
    }

    static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let blob = buffer.readLengthPrefixedSlice(as: UInt32.self) else {
            throw SSHError.unsupportedKey(String(localized: "Malformed RSA signature.", bundle: .module))
        }
        return Self(rawRepresentation: Data(blob.readableBytesView))
    }
}

extension ByteBuffer {
    /// An SSH `string`: a 32-bit length, then the bytes.
    @discardableResult
    mutating func writeSSHBytes(_ bytes: some Collection<UInt8>) -> Int {
        writeInteger(UInt32(bytes.count)) + writeBytes(bytes)
    }

    /// An SSH `mpint` from big-endian unsigned magnitude bytes.
    @discardableResult
    mutating func writeSSHMPInt(_ magnitude: Data) -> Int {
        var bytes = magnitude.drop(while: { $0 == 0 })
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: bytes.startIndex)
        }
        return writeSSHBytes(bytes)
    }
}
