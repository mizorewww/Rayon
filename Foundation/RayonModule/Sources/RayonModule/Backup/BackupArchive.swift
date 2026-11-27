//
//  BackupArchive.swift
//  RayonModule
//
//  The backup file: a ZIP with a manifest and its payload files. With a
//  password, every payload file is sealed with AES-GCM under a key derived
//  from it (PBKDF2-SHA256); the manifest says how. Reading unpacks into a
//  temporary folder and checks everything before anything is used.
//

import CommonCrypto
import CryptoKit
import Foundation
import ZIPFoundation

public enum BackupError: LocalizedError, Equatable {
    case notABackup
    case wrongKind
    case newerVersion
    case passwordRequired
    case wrongPassword
    case damaged(String)
    case secretsUnavailable

    public var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "This file is not a Rayon backup.", bundle: .module)
        case .wrongKind: String(localized: "This backup holds something else (data or settings) than what is being imported.", bundle: .module)
        case .newerVersion: String(localized: "This backup was made by a newer version of Rayon.", bundle: .module)
        case .passwordRequired: String(localized: "This backup is protected by a password.", bundle: .module)
        case .wrongPassword: String(localized: "The password is not the one this backup was protected with.", bundle: .module)
        case let .damaged(detail): String(localized: "The backup is damaged: \(detail)", bundle: .module)
        case .secretsUnavailable: String(localized: "Some passwords and keys cannot be read from the keychain now. Unlock the device and try again.", bundle: .module)
        }
    }
}

struct BackupManifest: Codable, Equatable {
    static let format = "me.mizorewww.rayon.backup"
    static let currentVersion = 1
    static let fileName = "manifest.json"

    enum Kind: String, Codable {
        /// Servers, identities, snippets, forwards, folders, known hosts.
        case data
        /// The app's preferences.
        case preferences
    }

    struct Encryption: Codable, Equatable {
        var kdf = "pbkdf2-sha256"
        var salt: Data
        var rounds: Int
    }

    var format = Self.format
    var version = Self.currentVersion
    var kind: Kind
    var created: Date
    var includesSecrets: Bool
    var encryption: Encryption?
}

/// Writes and reads the files of a backup.
enum BackupArchive {
    static let pbkdfRounds = 600_000
    /// The most rounds a backup may ask for: more would take minutes, and
    /// past UInt32 the count cannot even be passed on.
    static let maxPBKDFRounds = 10_000_000

    /// Zips `files` (name → contents) with a manifest into `url`; with a
    /// password each file is sealed.
    static func write(
        _ files: [String: Data],
        kind: BackupManifest.Kind,
        includesSecrets: Bool,
        password: String?,
        to url: URL
    ) throws {
        var manifest = BackupManifest(kind: kind, created: Date(), includesSecrets: includesSecrets)
        var key: SymmetricKey?
        if let password, !password.isEmpty {
            var salt = Data(count: 16)
            let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            guard status == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
            let encryption = BackupManifest.Encryption(salt: salt, rounds: pbkdfRounds)
            manifest.encryption = encryption
            key = try deriveKey(password: password, encryption: encryption)
        }

        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(BackupManifest.fileName))
        for (name, data) in files {
            let contents = try key.map { try CryptoKit.AES.GCM.seal(data, using: $0).combined ?? Data() } ?? data
            try contents.write(to: folder.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.zipItem(at: folder, to: url, shouldKeepParent: false)
    }

    /// Unpacks the backup at `url`, checks it is one of `kind` this version
    /// reads, and opens its files.
    static func read(
        _ url: URL,
        kind: BackupManifest.Kind,
        password: String?
    ) throws -> (manifest: BackupManifest, files: [String: Data]) {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.unzipItem(at: url, to: folder)
        } catch {
            throw BackupError.notABackup
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(BackupManifest.fileName)),
              let manifest = try? decoder.decode(BackupManifest.self, from: data),
              manifest.format == BackupManifest.format
        else { throw BackupError.notABackup }
        guard manifest.version <= BackupManifest.currentVersion else { throw BackupError.newerVersion }
        guard manifest.kind == kind else { throw BackupError.wrongKind }

        var key: SymmetricKey?
        if let encryption = manifest.encryption {
            guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
            key = try deriveKey(password: password, encryption: encryption)
        }
        var files: [String: Data] = [:]
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        for name in names where name != BackupManifest.fileName {
            let contents = try Data(contentsOf: folder.appendingPathComponent(name))
            if let key {
                do {
                    files[name] = try CryptoKit.AES.GCM.open(CryptoKit.AES.GCM.SealedBox(combined: contents), using: key)
                } catch {
                    throw BackupError.wrongPassword
                }
            } else {
                files[name] = contents
            }
        }
        return (manifest, files)
    }

    /// Whether the backup at `url` asks for a password, without opening it.
    static func isEncrypted(_ url: URL) -> Bool {
        guard let archive = try? Archive(url: url, accessMode: .read),
              let entry = archive[BackupManifest.fileName]
        else { return false }
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(BackupManifest.self, from: data))?.encryption != nil
    }

    static func deriveKey(password: String, encryption: BackupManifest.Encryption) throws -> SymmetricKey {
        guard encryption.kdf == "pbkdf2-sha256", !encryption.salt.isEmpty,
              (1 ... maxPBKDFRounds).contains(encryption.rounds)
        else {
            throw BackupError.damaged(String(localized: "unknown key derivation", bundle: .module))
        }
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { out in
            encryption.salt.withUnsafeBytes { salt in
                passwordData.withUnsafeBytes { pass in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pass.baseAddress?.assumingMemoryBound(to: CChar.self), passwordData.count,
                        salt.baseAddress?.assumingMemoryBound(to: UInt8.self), encryption.salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(encryption.rounds),
                        out.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.damaged(String(localized: "key derivation failed", bundle: .module)) }
        return SymmetricKey(data: derived)
    }

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayon-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
