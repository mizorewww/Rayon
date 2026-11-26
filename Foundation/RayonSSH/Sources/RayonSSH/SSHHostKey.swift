//
//  SSHHostKey.swift
//  RayonSSH
//

import Crypto
import Foundation
import NIOCore
import NIOSSH

/// A server's public host key as SSH sends it on the wire.
public struct SSHHostKey: Sendable, Hashable, Codable {
    /// The algorithm as SSH names it, "ssh-ed25519" for one.
    public let type: String
    /// The whole key blob, type string included, as in `known_hosts`.
    public let key: Data

    public init(type: String, key: Data) {
        self.type = type
        self.key = key
    }

    init(_ publicKey: NIOSSHPublicKey) {
        var buffer = ByteBuffer()
        publicKey.write(to: &buffer)
        let blob = Data(buffer.readableBytesView)
        var reader = buffer
        let type = reader.readLengthPrefixedSlice(as: UInt32.self).map { String(buffer: $0) } ?? "unknown"
        self.init(type: type, key: blob)
    }

    /// What `ssh-keygen -l` prints for the key.
    public var fingerprint: String {
        let digest = Data(SHA256.hash(data: key)).base64EncodedString()
        return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }
}

/// How a host key compares with the one saved for its address.
public enum SSHHostKeyStatus: Sendable, Equatable {
    case trusted
    /// Nothing is saved for the address yet.
    case unknown
    /// A different key is saved for the address.
    case changed(saved: SSHHostKey)
}
