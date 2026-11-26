//
//  UUID+Derived.swift
//  RayonModule
//
//  Ids that every device works out alike for the same thing (a UU device's
//  server, a folder each device makes on its own), so iCloud sync keeps one
//  record of it rather than one per device.
//

import CryptoKit
import Foundation

extension UUID {
    /// A name-based UUID (version 5 layout, RFC 4122 variant) from SHA-256
    /// of `name`.
    init(derivedFrom name: String) {
        let hash = Array(SHA256.hash(data: Data(name.utf8)))
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
