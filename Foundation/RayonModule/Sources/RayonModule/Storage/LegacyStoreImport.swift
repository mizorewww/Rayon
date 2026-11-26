//
//  LegacyStoreImport.swift
//  RayonModule
//
//  Moves what the previous releases kept — groups of records sealed under a
//  master key in the keychain and stored in UserDefaults — into the database
//  and the keychain, once, on the first launch after the update, then
//  removes the old values. 2.8 rewrote a group only when it changed, so a
//  group may still be in any format an older release wrote (AES-CBC, then
//  AES-GCM "RGCM1", then "RGCM2"), and a server's settings may still be in
//  its attachment. All of it is read, or nothing is imported.
//
//

import BetterCodable
import CommonCrypto
import CryptoKit
import Foundation
import Security
@preconcurrency import WCDBSwift

enum LegacyStoreImport {
    static let doneKey = "me.mizorewww.rayon.storage.legacyImported"

    enum Key {
        static let machines = "machineGroupEncrypted"
        static let identities = "identityGroupEncrypted"
        static let snippets = "snippetGroupEncrypted"
        static let portForwards = "portForwardEncrypted"
        static let folders = "folderGroupEncrypted"
        static let recent = "recentRecordEncrypted"
        static let knownHosts = "me.mizorewww.rayon.knownHosts"

        static let sealed = [machines, identities, snippets, portForwards, folders, recent, knownHosts]
        /// Left behind by the previous releases and read by nothing now.
        /// (The redaction level and "open interface automatically" were
        /// meant to be sealed too, but a property list cannot hold a bare
        /// number or flag, so they never were written.)
        static let obsolete = [
            "machineRedacted", "openInterfaceAutomatically",
            "me.mizorewww.rayon.sync.settings", "me.mizorewww.rayon.debug.sync",
        ]
    }

    /// The keychain items that held the master key: the name used since
    /// 2.5, then the one before it, which 2.8 still read.
    static let masterKeyItems: [(service: String, account: String)] = [
        ("me.mizorewww.rayon.kcAccess", "me.mizorewww.rayon.MasterCrypto"),
        ("wiki.qaq.rayon.kcAccess", "wiki.qaq.rayon.MasterCrypto"),
    ]

    enum Outcome: Equatable {
        /// There was nothing (left) to import.
        case nothingToImport
        case imported
        /// The old data is there and stays there, but could not be
        /// imported; the next launch tries again. Says why, for the user.
        case blocked(String)
    }

    /// Imports what the previous release stored, if it has not been. Without
    /// the master key, or when any of it cannot be read, nothing is touched
    /// and the next launch tries again.
    @discardableResult
    static func runIfNeeded(
        into storage: RayonStorage,
        defaults: UserDefaults = .standard,
        masterKey: () -> String? = { readMasterKey() },
        forgetMasterKey: () -> Void = { removeMasterKey() }
    ) -> Outcome {
        guard !defaults.bool(forKey: doneKey) else { return .nothingToImport }
        guard Key.sealed.contains(where: { defaults.object(forKey: $0) != nil }) else {
            defaults.set(true, forKey: doneKey)
            return .nothingToImport
        }
        let lead = "The servers, identities and snippets saved by the previous version of Rayon could not be opened"
        let kept = "They are kept as they are, and Rayon tries again on its next launch."
        guard let master = masterKey(), !master.isEmpty else {
            RayonStorage.logger.error("legacy import: the master key is not readable; trying again on the next launch")
            return .blocked("\(lead): the key that protects them could not be read from the keychain. \(kept)")
        }
        let opener = Opener(masterKey: master)
        let copies: [String]
        do {
            copies = try importRecords(from: defaults, opener: opener, into: storage)
        } catch {
            RayonStorage.logger.error("legacy import failed: \(error.localizedDescription)")
            return .blocked("\(lead) (\(error.localizedDescription)). \(kept)")
        }
        for key in Key.sealed + Key.obsolete + copies {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: doneKey)
        forgetMasterKey()
        return .imported
    }

    enum Failure: LocalizedError {
        case unreadable(key: String)

        var errorDescription: String? {
            switch self {
            case let .unreadable(key):
                let names = [
                    Key.machines: "servers", Key.identities: "identities", Key.snippets: "snippets",
                    Key.portForwards: "port forwards", Key.folders: "folders",
                    Key.recent: "recent connections", Key.knownHosts: "host keys",
                ]
                return "its \(names[key] ?? key) could not be decrypted or read"
            }
        }
    }

    /// Returns the keys of the copies 2.8 set aside that were imported.
    private static func importRecords(from defaults: UserDefaults, opener: Opener, into storage: RayonStorage) throws -> [String] {
        /// A value that is there but cannot be read stops the import: the
        /// rest is not worth losing it for.
        func open<T: Decodable>(_ key: String, as _: T.Type) throws -> T? {
            guard let object = defaults.object(forKey: key) else { return nil }
            guard let sealed = object as? Data,
                  let plain = opener.open(sealed),
                  let value = try? PropertyListDecoder().decode(T.self, from: plain)
            else { throw Failure.unreadable(key: key) }
            return value
        }

        /// 2.8 set a value it could not read aside under "<key>.corrupt" and
        /// started the key afresh, so the copy may hold the only record of
        /// what the user had. One that opens now is imported after the
        /// value itself (whose records win); one that does not stays.
        var copies: [String] = []
        func openCopy<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            let copy = key + ".corrupt"
            guard let value = try? open(copy, as: type) else { return nil }
            copies.append(copy)
            return value
        }
        func both<Group: Decodable, Element>(_ key: String, as type: Group.Type, _ elements: (Group) -> [Element]) throws -> [Element] {
            try (open(key, as: type).map(elements) ?? []) + (openCopy(key, as: type).map(elements) ?? [])
        }

        var seenMachines = Set<UUID>()
        let machines = try both(Key.machines, as: MachineGroup.self, \.machines).filter { seenMachines.insert($0.id).inserted }
        let identities = try both(Key.identities, as: IdentityGroup.self, \.identities)
        let snippets = try both(Key.snippets, as: SnippetGroup.self, \.snippets)
        let forwards = try both(Key.portForwards, as: PortForwardGroup.self, \.forwards)
        var folders = try both(Key.folders, as: FolderGroup.self, \.folders).map(\.folder)
        let recent = try open(Key.recent, as: [RayonStore.RecentConnection].self) ?? openCopy(Key.recent, as: [RayonStore.RecentConnection].self)
        // Before 2.5 the host keys were a plain dictionary.
        let ownHosts = try (defaults.object(forKey: Key.knownHosts) as? [String: String]) ?? open(Key.knownHosts, as: [String: String].self)
        let hosts = (openCopy(Key.knownHosts, as: [String: String].self) ?? [:]).merging(ownHosts ?? [:]) { _, own in own }

        let folderIDs = addFolders(namedBy: machines, to: &folders)

        // All of it or none. What the database already has stays as it is:
        // the user may have added or changed things while the old values
        // could not be read, or the flag was lost and they come again.
        let now = Date()
        try storage.insertMissing { inserter in
            func insert<T: StoredRecord>(_ record: T) throws {
                try inserter.insert(record, modified: importedDate(of: record))
            }
            try folders.forEach(insert)
            try identities.map(\.identity).forEach(insert)
            // An old store could hold jumps that loop; such a server could
            // never be saved again.
            try RDMachine.breakingProxyJumpLoops(machines.map { $0.machine(folderId: folderIDs[$0.group]) }).forEach(insert)
            try snippets.map(\.snippet).forEach(insert)
            try forwards.map(\.forward).forEach(insert)
            let handle = inserter.handle
            if let recent, try handle.getValue(on: Column(named: "id").count(), fromTable: RecentConnectionRecord.tableName).intValue == 0 {
                try handle.insert(recent.enumerated().map { $1.record(at: $0) }, intoTable: RecentConnectionRecord.tableName)
            }
            for (name, line) in hosts {
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let key = Data(base64Encoded: String(parts[1])) else { continue }
                let host = KnownHostRecord(name: name, type: String(parts[0]), key: key, added: now, legacy: true)
                try handle.insertOrIgnore([host], intoTable: KnownHostRecord.tableName)
            }
        }
        return copies
    }

    /// A server named its folder; a name no folder records is a folder too.
    /// The old folders synced by name, each device under its own id: the
    /// id comes from the name now, the same on every device. Returns the
    /// folders' ids by name.
    static func addFolders(namedBy machines: [Machine], to folders: inout [RDFolder]) -> [String: RDFolder.ID] {
        for name in Set(machines.map(\.group)) where !name.isEmpty && !folders.contains(where: { $0.name == name }) {
            folders.append(RDFolder(id: RDFolder.id(named: name), name: name))
        }
        return Dictionary(folders.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    /// When an imported record counts as changed: long before anything
    /// changed since, so a device that updates late never wins over an edit
    /// made on another one. The time is worked out from the record's
    /// content: two devices importing the same record agree on it, and
    /// when their copies differ, every device keeps the same one.
    static func importedDate<T: StoredRecord>(of record: T) -> Date {
        let milliseconds = SHA256.hash(data: record.syncedContentData).prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Date(timeIntervalSinceReferenceDate: TimeInterval(milliseconds) / 1000)
    }

    // MARK: - The previous releases' encryption

    /// What 2.8's AES engine read, under the master key:
    /// - "RGCM2": AES-256-GCM under a key derived with HKDF-SHA256 (2.7, 2.8);
    /// - "RGCM1": AES-256-GCM under the key string itself, cut or repeated
    ///   to 32 characters (2.5 to 2.6.2);
    /// - no prefix: AES-CBC with PKCS7 padding under that key, and the key
    ///   cut or repeated to 16 characters as the IV (up to 2.4).
    struct Opener {
        static let prefix = Data("RGCM2".utf8)
        static let gcm1Prefix = Data("RGCM1".utf8)
        let key: SymmetricKey
        let legacyKey: Data?
        let legacyIV: Data?

        init(masterKey: String) {
            key = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: Data(masterKey.utf8)),
                salt: Data("me.mizorewww.rayon.aes.hkdf.v2".utf8),
                info: Data("catussh-aes-256-gcm".utf8),
                outputByteCount: 32
            )
            // As those releases did it: in characters, then as UTF-8.
            func fitted(_ string: String, to count: Int) -> Data {
                var string = string
                while string.count < count { string += string }
                while string.count > count { string.removeLast() }
                return Data(string.utf8)
            }
            if masterKey.count >= kCCKeySizeAES128 {
                legacyKey = fitted(masterKey, to: 32)
                legacyIV = fitted(masterKey, to: kCCBlockSizeAES128)
            } else {
                legacyKey = nil
                legacyIV = nil
            }
        }

        func open(_ data: Data) -> Data? {
            if data.starts(with: Self.prefix) {
                return openGCM(data.dropFirst(Self.prefix.count), key: key)
            }
            if data.starts(with: Self.gcm1Prefix) {
                return legacyKey.flatMap { openGCM(data.dropFirst(Self.gcm1Prefix.count), key: SymmetricKey(data: $0)) }
            }
            return openCBC(data)
        }

        private func openGCM(_ combined: Data, key: SymmetricKey) -> Data? {
            guard let box = try? CryptoKit.AES.GCM.SealedBox(combined: combined) else { return nil }
            return try? CryptoKit.AES.GCM.open(box, using: key)
        }

        private func openCBC(_ data: Data) -> Data? {
            guard let legacyKey, let legacyIV else { return nil }
            var plain = Data(count: data.count + kCCBlockSizeAES128)
            var length = 0
            let status = plain.withUnsafeMutableBytes { out in
                data.withUnsafeBytes { input in
                    legacyIV.withUnsafeBytes { iv in
                        legacyKey.withUnsafeBytes { key in
                            CCCrypt(
                                CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, legacyKey.count, iv.baseAddress,
                                input.baseAddress, data.count, out.baseAddress, out.count, &length
                            )
                        }
                    }
                }
            }
            guard status == kCCSuccess else { return nil }
            return plain.prefix(length)
        }
    }

    /// The first master key found, as 2.8 looked for it.
    static func readMasterKey(from items: [(service: String, account: String)] = masterKeyItems) -> String? {
        for item in items {
            var result: CFTypeRef?
            let status = SecItemCopyMatching([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data,
               let key = String(data: data, encoding: .utf8), key.count > 2
            {
                return key
            }
        }
        return nil
    }

    /// The master keys. The passphrase key the old iCloud sync kept stays:
    /// it is in the iCloud keychain, and removing it here would remove it
    /// from the devices still on 2.8, which then wait for it for good.
    static func removeMasterKey(items: [(service: String, account: String)] = masterKeyItems) {
        for item in items {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account,
            ] as CFDictionary)
        }
    }
}

// MARK: - The previous release's records

extension LegacyStoreImport {
    enum EmptyAttachment: DefaultCodableStrategy { static var defaultValue: [String: String] { [:] } }

    struct MachineGroup: Decodable { @LossyArray var machines: [Machine] }
    struct IdentityGroup: Decodable { @LossyArray var identities: [Identity] }
    struct SnippetGroup: Decodable { @LossyArray var snippets: [Snippet] }
    struct PortForwardGroup: Decodable { @LossyArray var forwards: [PortForward] }
    struct FolderGroup: Decodable { @LossyArray var folders: [Folder] }

    /// 2.8 wrote a field only when it differed from its default; releases
    /// before 2.7 kept these settings in the attachment, which 2.8 still
    /// read them from. Both are read here as 2.8 did.
    struct Machine: Decodable {
        var id: UUID
        var remoteAddress: String
        var remotePort: String
        var name: String
        var group: String
        var lastConnection: Date
        var lastBanner: String
        var comment: String
        var associatedIdentity: String?
        var sshUsername: String
        var fileTransferLoginPath: String
        var transport: String
        var cloudflareServiceTokenID: String
        var cloudflareServiceTokenSecret: String
        var remoteDesktopProtocol: String
        var vncPort: String
        var vncPassword: String
        var vncUsername: String
        var vncShared: Bool
        var vncOverSSH: Bool
        var uuDeviceID: String
        var uuDeviceAlias: String
        var uuAnonymousDeviceID: String
        var uuAssistID: String
        var uuAssistCode: String
        var uuDisplayID: Int
        var uuFPS: Int
        var uuQuality: Int
        var uuTrueColor: Bool
        var uuManaged: Bool
        var ghosttyTerminfoVersion: String?
        var proxyJumpMachineID: String?

        private enum CodingKeys: String, CodingKey {
            case id, remoteAddress, remotePort, name, group, lastConnection, lastBanner, comment
            case associatedIdentity, sshUsername, attachment, fileTransferLoginPath, transport
            case cloudflareServiceTokenID, cloudflareServiceTokenSecret, remoteDesktopProtocol
            case vncPort, vncPassword, vncUsername, vncShared, vncOverSSH
            case uuDeviceID, uuDeviceAlias, uuAnonymousDeviceID, uuAssistID, uuAssistCode
            case uuDisplayID, uuFPS, uuQuality, uuTrueColor, uuManaged, ghosttyTerminfoVersion, proxyJumpMachineID
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let attachment = try c.decodeIfPresent([String: String].self, forKey: .attachment) ?? [:]
            func string(_ key: CodingKeys, _ legacy: String, _ fallback: String) throws -> String {
                try c.decodeIfPresent(String.self, forKey: key) ?? attachment[legacy] ?? fallback
            }
            func int(_ key: CodingKeys, _ legacy: String, _ fallback: Int) throws -> Int {
                try c.decodeIfPresent(Int.self, forKey: key) ?? attachment[legacy].flatMap(Int.init) ?? fallback
            }
            id = try c.decode(UUID.self, forKey: .id)
            remoteAddress = try c.decode(String.self, forKey: .remoteAddress)
            remotePort = try c.decode(String.self, forKey: .remotePort)
            name = try c.decode(String.self, forKey: .name)
            group = try c.decode(String.self, forKey: .group)
            lastConnection = try c.decode(Date.self, forKey: .lastConnection)
            lastBanner = try c.decode(String.self, forKey: .lastBanner)
            comment = try c.decode(String.self, forKey: .comment)
            associatedIdentity = try c.decodeIfPresent(String.self, forKey: .associatedIdentity)
            sshUsername = try c.decodeIfPresent(String.self, forKey: .sshUsername) ?? ""
            fileTransferLoginPath = try string(.fileTransferLoginPath, "sftp.login.path", "/")
            transport = try string(.transport, "transport", "")
            cloudflareServiceTokenID = try string(.cloudflareServiceTokenID, "cloudflare.serviceToken.id", "")
            cloudflareServiceTokenSecret = try string(.cloudflareServiceTokenSecret, "cloudflare.serviceToken.secret", "")
            remoteDesktopProtocol = try string(.remoteDesktopProtocol, "remoteDesktop.protocol", "")
            vncPort = try string(.vncPort, "remoteDesktop.vnc.port", "5900")
            vncPassword = try string(.vncPassword, "remoteDesktop.vnc.password", "")
            vncUsername = try string(.vncUsername, "remoteDesktop.vnc.username", "")
            vncShared = try c.decodeIfPresent(Bool.self, forKey: .vncShared) ?? (attachment["remoteDesktop.vnc.shared"].map { $0 != "0" } ?? true)
            vncOverSSH = try c.decodeIfPresent(Bool.self, forKey: .vncOverSSH) ?? (attachment["remoteDesktop.vnc.overSSH"] == "1")
            uuDeviceID = try string(.uuDeviceID, "remoteDesktop.uu.deviceID", "")
            uuDeviceAlias = try string(.uuDeviceAlias, "remoteDesktop.uu.deviceAlias", "")
            uuAnonymousDeviceID = try string(.uuAnonymousDeviceID, "remoteDesktop.uu.anonymousDeviceID", "")
            uuAssistID = try string(.uuAssistID, "remoteDesktop.uu.assistID", "")
            uuAssistCode = try string(.uuAssistCode, "remoteDesktop.uu.assistCode", "")
            uuDisplayID = try int(.uuDisplayID, "remoteDesktop.uu.displayID", 0)
            uuFPS = try int(.uuFPS, "remoteDesktop.uu.fps", 60)
            uuQuality = try int(.uuQuality, "remoteDesktop.uu.quality", 5)
            uuTrueColor = try c.decodeIfPresent(Bool.self, forKey: .uuTrueColor) ?? false
            uuManaged = try c.decodeIfPresent(Bool.self, forKey: .uuManaged) ?? (attachment["remoteDesktop.uu.managed"] == "1")
            ghosttyTerminfoVersion = try c.decodeIfPresent(String.self, forKey: .ghosttyTerminfoVersion) ?? attachment["terminal.terminfo"]
            proxyJumpMachineID = try c.decodeIfPresent(String.self, forKey: .proxyJumpMachineID) ?? attachment["proxyJump.machineID"]
        }

        func machine(folderId: UUID?) -> RDMachine {
            var machine = RDMachine(
                id: id,
                remoteAddress: remoteAddress,
                remotePort: remotePort,
                name: name,
                folderId: folderId,
                lastConnection: lastConnection,
                lastBanner: lastBanner,
                comment: comment,
                associatedIdentity: associatedIdentity.flatMap(UUID.init(uuidString:)),
                sshUsername: sshUsername
            )
            machine.fileTransferLoginPath = fileTransferLoginPath
            machine.transport = RDMachine.Transport(rawValue: transport) ?? .direct
            machine.cloudflareServiceTokenID = cloudflareServiceTokenID
            machine.cloudflareServiceTokenSecret = cloudflareServiceTokenSecret
            machine.remoteDesktopProtocol = RDMachine.RemoteDesktopProtocolType(rawValue: remoteDesktopProtocol) ?? .none
            machine.vncPort = vncPort
            machine.vncPassword = vncPassword
            machine.vncUsername = vncUsername
            machine.vncShared = vncShared
            machine.vncOverSSH = vncOverSSH
            machine.uuDeviceID = uuDeviceID
            machine.uuDeviceAlias = uuDeviceAlias
            machine.uuAnonymousDeviceID = uuAnonymousDeviceID
            machine.uuAssistID = uuAssistID
            machine.uuAssistCode = uuAssistCode
            machine.uuDisplayID = uuDisplayID
            machine.uuFPS = uuFPS
            machine.uuQuality = uuQuality
            machine.uuTrueColor = uuTrueColor
            machine.uuManaged = uuManaged
            machine.ghosttyTerminfoVersion = ghosttyTerminfoVersion
            machine.proxyJumpMachineID = proxyJumpMachineID.flatMap(UUID.init(uuidString:))
            // A jump to itself is the shortest loop there is.
            if machine.proxyJumpMachineID == machine.id { machine.proxyJumpMachineID = nil }
            return machine
        }
    }

    struct Identity: Decodable {
        var id: UUID
        var username: String
        var password: String
        var privateKey: String
        var publicKey: String
        var lastRecentUsed: Date
        var comment: String
        var group: String
        var authenticAutomatically: Bool
        @DefaultCodable<EmptyAttachment> var attachment: [String: String]

        var identity: RDIdentity {
            RDIdentity(
                id: id,
                username: username,
                password: password,
                privateKey: privateKey,
                publicKey: publicKey,
                lastRecentUsed: lastRecentUsed,
                comment: comment,
                group: group,
                authenticAutomatically: authenticAutomatically,
                useSSHAgent: attachment["auth.sshAgent"] == "1"
            )
        }
    }

    struct Snippet: Decodable {
        var id: UUID
        var name: String
        var group: String
        var code: String
        var comment: String
        @DefaultCodable<EmptyAttachment> var attachment: [String: String]

        var snippet: RDSnippet {
            RDSnippet(id: id, name: name, group: group, code: code, comment: comment, symbol: attachment["sfAvatar"] ?? "")
        }
    }

    struct PortForward: Decodable {
        var id: UUID
        var forwardOrientation: RDPortForward.ForwardOrientation
        var bindPort: Int
        var targetHost: String
        var targetPort: Int
        var usingMachine: UUID?

        var forward: RDPortForward {
            RDPortForward(
                id: id,
                forwardOrientation: forwardOrientation,
                bindPort: bindPort,
                targetHost: targetHost,
                targetPort: targetPort,
                usingMachine: usingMachine
            )
        }
    }

    struct Folder: Decodable {
        enum Source: Decodable {
            case local
            case uuRemote(userID: String)
        }

        var id: UUID
        var name: String
        var source: Source

        /// Under an id worked out from the name, or from the account.
        var folder: RDFolder {
            switch source {
            case .local: RDFolder(id: RDFolder.id(named: name), name: name)
            case let .uuRemote(userID): RDFolder(id: RDFolder.id(uuUserID: userID), name: name, source: .uuRemote(userID: userID))
            }
        }
    }
}
