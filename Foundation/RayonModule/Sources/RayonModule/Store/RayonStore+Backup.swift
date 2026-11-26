//
//  RayonStore+Backup.swift
//  RayonModule
//

import Foundation

public extension RayonStore {
    struct BackupArchive: Codable {
        var version: Int = 2
        var exportedAt: Date = .init()
        var folders: [RecordPayload<RDFolder>]
        var identities: [RecordPayload<RDIdentity>]
        var machines: [RecordPayload<RDMachine>]
        var snippets: [RecordPayload<RDSnippet>]
        var portForwards: [RecordPayload<RDPortForward>]
    }

    /// Exports all saved servers, identities, snippets, port forwards, and folders.
    func exportBackupData(passphrase: String = "") throws -> Data {
        let archive = BackupArchive(
            folders: folders.map(RecordPayload.init),
            identities: identities.map(RecordPayload.init),
            machines: machines.map(RecordPayload.init),
            snippets: snippets.map(RecordPayload.init),
            portForwards: portForwards.map(RecordPayload.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(archive)
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        guard let aes = AES(key: trimmed), let encrypted = aes.encrypt(data: raw) else {
            throw CocoaError(.coderInvalidValue)
        }
        return encrypted
    }

    /// Imports a backup archive, merging or replacing items by UUID.
    @discardableResult
    func importBackupData(_ data: Data, passphrase: String = "") throws -> (machines: Int, identities: Int, snippets: Int, forwards: Int) {
        var payload = data
        if data.starts(with: Data("RGCM".utf8)) {
            let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let aes = AES(key: trimmed), let plain = aes.decrypt(data: data) else {
                throw CocoaError(.coderReadCorrupt)
            }
            payload = plain
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BackupArchive.self, from: payload)
        archive.folders.forEach { save($0.resolved) }
        archive.identities.forEach { save($0.resolved) }
        archive.machines.forEach { save($0.resolved) }
        archive.snippets.forEach { save($0.resolved) }
        archive.portForwards.forEach { save($0.resolved) }
        return (archive.machines.count, archive.identities.count, archive.snippets.count, archive.portForwards.count)
    }
}
