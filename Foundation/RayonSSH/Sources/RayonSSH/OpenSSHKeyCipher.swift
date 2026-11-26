//
//  OpenSSHKeyCipher.swift
//  RayonSSH
//
//  Decrypts the private section of a passphrase-protected OpenSSH key, of
//  any key type: bcrypt-pbkdf (Citadel's, from OpenBSD) turns the
//  passphrase into a key and IV, and the section is AES in CTR or CBC mode
//  (CommonCrypto) or GCM (CryptoKit), as ssh-keygen writes it.
//

import CCitadelBcrypt
import CommonCrypto
import Crypto
import Foundation

enum OpenSSHKeyCipher {
    private enum Mode { case ctr, cbc, gcm }

    static func decrypt(_ section: [UInt8], tag: [UInt8], cipher: String, passphrase: [UInt8], salt: [UInt8], rounds: UInt32) throws -> [UInt8] {
        let (mode, keyLength): (Mode, Int) = switch cipher {
        case "aes128-ctr": (.ctr, 16)
        case "aes192-ctr": (.ctr, 24)
        case "aes256-ctr": (.ctr, 32)
        case "aes128-cbc": (.cbc, 16)
        case "aes192-cbc": (.cbc, 24)
        case "aes256-cbc": (.cbc, 32)
        case "aes128-gcm@openssh.com": (.gcm, 16)
        case "aes256-gcm@openssh.com": (.gcm, 32)
        default:
            throw SSHError.unsupportedKey("Keys encrypted with \(cipher) are not supported. Re-encrypt it with `ssh-keygen -p -Z aes256-ctr -f <key>`.")
        }
        let ivLength = mode == .gcm ? 12 : 16
        let derived = try deriveKey(passphrase: passphrase, salt: salt, rounds: rounds, length: keyLength + ivLength)
        let key = Array(derived[..<keyLength])
        let iv = Array(derived[keyLength...])
        switch mode {
        case .gcm:
            guard tag.count >= 16 else { throw SSHError.unsupportedKey("The private key is damaged or incomplete.") }
            do {
                let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: section, tag: tag.prefix(16))
                return try Array(AES.GCM.open(box, using: SymmetricKey(data: key)))
            } catch {
                throw SSHError.unsupportedKey("The private key could not be decrypted. Check the identity's password, which is the key's passphrase.")
            }
        case .ctr, .cbc:
            return try commonCrypto(section, key: key, iv: iv, mode: mode == .ctr ? CCMode(kCCModeCTR) : CCMode(kCCModeCBC))
        }
    }

    private static func commonCrypto(_ input: [UInt8], key: [UInt8], iv: [UInt8], mode: CCMode) throws -> [UInt8] {
        var cryptor: CCCryptorRef?
        let created = CCCryptorCreateWithMode(
            CCOperation(kCCDecrypt), mode, CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
            iv, key, key.count, nil, 0, 0, CCModeOptions(mode == CCMode(kCCModeCTR) ? kCCModeOptionCTR_BE : 0), &cryptor
        )
        guard created == kCCSuccess, let cryptor else { throw SSHError.unsupportedKey("The private key could not be decrypted.") }
        defer { CCCryptorRelease(cryptor) }
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let status = CCCryptorUpdate(cryptor, input, input.count, &output, output.count, &moved)
        guard status == kCCSuccess, moved == input.count else { throw SSHError.unsupportedKey("The private key could not be decrypted.") }
        return output
    }

    /// Citadel's bcrypt-pbkdf hashes with a SHA-512 function it is handed.
    private static let hashInstalled: Void = {
        citadel_set_crypto_hash_sha512 { output, input, length in
            guard let output else { return }
            _ = CC_SHA512(input, CC_LONG(length), output)
        }
    }()

    private static func deriveKey(passphrase: [UInt8], salt: [UInt8], rounds: UInt32, length: Int) throws -> [UInt8] {
        _ = hashInstalled
        var derived = [UInt8](repeating: 0, count: length)
        guard citadel_bcrypt_pbkdf(passphrase, passphrase.count, salt, salt.count, &derived, length, rounds) == 0 else {
            throw SSHError.unsupportedKey("The private key could not be decrypted.")
        }
        return derived
    }
}
