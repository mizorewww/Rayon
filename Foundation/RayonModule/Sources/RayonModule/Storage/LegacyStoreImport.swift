//
//  LegacyStoreImport.swift
//  RayonModule
//
//  Moves what the previous release kept — groups of records sealed with
//  AES-GCM under a master key in the keychain and stored in UserDefaults —
//  into the database and the keychain, once, on the first launch after the
//  update, then removes the old values. It reads that release's format only.
//  The whole file goes away once no one updates from that release any more.
//

import BetterCodable
import CryptoKit
import Foundation
import Security

enum LegacyStoreImport {
    static let doneKey = "me.mizorewww.rayon.storage.legacyImported"

    enum Key {
        static let machines = "machineGroupEncrypted"
        static let identities = "identityGroupEncrypted"
        static let snippets = "snippetGroupEncrypted"
        static let portForwards = "portForwardEncrypted"
        static let folders = "folderGroupEncrypted"
        static let recent = "recentRecordEncrypted"
        static let redacted = "machineRedacted"
        static let openInterface = "openInterfaceAutomatically"
        static let knownHosts = "me.mizorewww.rayon.knownHosts"

        static let sealed = [machines, identities, snippets, portForwards, folders, recent, redacted, openInterface, knownHosts]
        /// Left behind by the previous release and read by nothing now.
        static let obsolete = [
            "me.mizorewww.rayon.sync.settings", "me.mizorewww.rayon.debug.sync",
        ] + sealed.map { $0 + ".corrupt" }
    }

    /// The keychain item that held the master key.
    static let masterKeyService = "me.mizorewww.rayon.kcAccess"
    static let masterKeyAccount = "me.mizorewww.rayon.MasterCrypto"

    /// Imports what the previous release stored, if it has not been. Without
    /// the master key nothing is touched, and the next launch tries again.
    @discardableResult
    static func runIfNeeded(
        into storage: RayonStorage,
        defaults: UserDefaults = .standard,
        masterKey: () -> String? = readMasterKey,
        forgetMasterKey: () -> Void = removeMasterKey
    ) -> Bool {
        guard !defaults.bool(forKey: doneKey) else { return false }
        // The database is what counts: once it holds anything (imported
        // before, or saved since), the old values never come over it, even
        // when the flag above was lost or the defaults are shared.
        guard !storage.hasAnyRecord else {
            defaults.set(true, forKey: doneKey)
            return false
        }
        guard Key.sealed.contains(where: { defaults.object(forKey: $0) != nil }) else {
            defaults.set(true, forKey: doneKey)
            return false
        }
        guard let master = masterKey(), !master.isEmpty else {
            RayonStorage.logger.error("legacy import: the master key is not readable; trying again on the next launch")
            return false
        }
        let opener = Opener(masterKey: master)
        do {
            try importRecords(from: defaults, opener: opener, into: storage)
        } catch {
            RayonStorage.logger.error("legacy import failed: \(error.localizedDescription)")
            return false
        }
        for key in Key.sealed + Key.obsolete {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: doneKey)
        forgetMasterKey()
        return true
    }

    private static func importRecords(from defaults: UserDefaults, opener: Opener, into storage: RayonStorage) throws {
        func open<T: Decodable>(_ key: String, as _: T.Type) -> T? {
            guard let sealed = defaults.data(forKey: key) else { return nil }
            guard let plain = opener.open(sealed) else {
                RayonStorage.logger.error("legacy import: \(key) could not be decrypted")
                return nil
            }
            do {
                return try PropertyListDecoder().decode(T.self, from: plain)
            } catch {
                RayonStorage.logger.error("legacy import: \(key) could not be read: \(error.localizedDescription)")
                return nil
            }
        }

        let machines = open(Key.machines, as: MachineGroup.self)?.machines ?? []
        let identities = open(Key.identities, as: IdentityGroup.self)?.identities ?? []
        let snippets = open(Key.snippets, as: SnippetGroup.self)?.snippets ?? []
        let forwards = open(Key.portForwards, as: PortForwardGroup.self)?.forwards ?? []
        var folders = (open(Key.folders, as: FolderGroup.self)?.folders ?? []).map(\.folder)

        // A server named its folder; a name no folder records is a folder too.
        for name in Set(machines.map(\.group)) where !name.isEmpty && !folders.contains(where: { $0.name == name }) {
            folders.append(RDFolder(name: name))
        }
        let folderIDs = Dictionary(folders.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })

        for folder in folders {
            try storage.save(folder)
        }
        for identity in identities {
            try storage.save(identity.identity)
        }
        for machine in machines {
            try storage.save(machine.machine(folderId: folderIDs[machine.group]))
        }
        for snippet in snippets {
            try storage.save(snippet.snippet)
        }
        for forward in forwards {
            try storage.save(forward.forward)
        }

        if let recent = open(Key.recent, as: [RayonStore.RecentConnection].self) {
            try storage.saveRecentConnections(recent.enumerated().map { $1.record(at: $0) })
        }
        if let level = open(Key.redacted, as: Int.self) {
            defaults.set(level, forKey: RayonStore.Key.machineRedacted)
        }
        if let open = open(Key.openInterface, as: Bool.self) {
            defaults.set(open, forKey: RayonStore.Key.openInterfaceAutomatically)
        }
        if let hosts = open(Key.knownHosts, as: [String: String].self) {
            for (name, line) in hosts {
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let key = Data(base64Encoded: String(parts[1])) else { continue }
                try storage.saveKnownHost(KnownHostRecord(name: name, type: String(parts[0]), key: key, added: Date()))
            }
        }
    }

    // MARK: - The previous release's encryption

    /// AES-256-GCM under a key derived with HKDF-SHA256 from the master key,
    /// prefixed "RGCM2".
    struct Opener {
        static let prefix = Data("RGCM2".utf8)
        let key: SymmetricKey

        init(masterKey: String) {
            key = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: Data(masterKey.utf8)),
                salt: Data("me.mizorewww.rayon.aes.hkdf.v2".utf8),
                info: Data("catussh-aes-256-gcm".utf8),
                outputByteCount: 32
            )
        }

        func open(_ data: Data) -> Data? {
            guard data.starts(with: Self.prefix),
                  let box = try? CryptoKit.AES.GCM.SealedBox(combined: data.dropFirst(Self.prefix.count))
            else { return nil }
            return try? CryptoKit.AES.GCM.open(box, using: key)
        }

        /// What the previous release wrote, for tests.
        func seal(_ data: Data) throws -> Data {
            guard let combined = try CryptoKit.AES.GCM.seal(data, using: key).combined else {
                throw CocoaError(.coderInvalidValue)
            }
            return Self.prefix + combined
        }
    }

    static func readMasterKey() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The master key, and the passphrase key the old iCloud sync kept in
    /// the iCloud keychain.
    static func removeMasterKey() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: masterKeyAccount,
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "me.mizorewww.rayon.sync.key",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ] as CFDictionary)
    }
}

// MARK: - The previous release's records

extension LegacyStoreImport {
    enum EmptyString: DefaultCodableStrategy { static var defaultValue: String { "" } }
    enum Slash: DefaultCodableStrategy { static var defaultValue: String { "/" } }
    enum VNCPort: DefaultCodableStrategy { static var defaultValue: String { "5900" } }
    enum Zero: DefaultCodableStrategy { static var defaultValue: Int { 0 } }
    enum Five: DefaultCodableStrategy { static var defaultValue: Int { 5 } }
    enum Sixty: DefaultCodableStrategy { static var defaultValue: Int { 60 } }
    enum EmptyAttachment: DefaultCodableStrategy { static var defaultValue: [String: String] { [:] } }

    struct MachineGroup: Decodable { @LossyArray var machines: [Machine] }
    struct IdentityGroup: Decodable { @LossyArray var identities: [Identity] }
    struct SnippetGroup: Decodable { @LossyArray var snippets: [Snippet] }
    struct PortForwardGroup: Decodable { @LossyArray var forwards: [PortForward] }
    struct FolderGroup: Decodable { @LossyArray var folders: [Folder] }

    /// The previous release wrote a field only when it differed from its
    /// default; the defaults stand in for the rest.
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
        @DefaultCodable<EmptyString> var sshUsername: String
        @DefaultCodable<Slash> var fileTransferLoginPath: String
        @DefaultCodable<EmptyString> var transport: String
        @DefaultCodable<EmptyString> var cloudflareServiceTokenID: String
        @DefaultCodable<EmptyString> var cloudflareServiceTokenSecret: String
        @DefaultCodable<EmptyString> var remoteDesktopProtocol: String
        @DefaultCodable<VNCPort> var vncPort: String
        @DefaultCodable<EmptyString> var vncPassword: String
        @DefaultCodable<EmptyString> var vncUsername: String
        @DefaultTrue var vncShared: Bool
        @DefaultFalse var vncOverSSH: Bool
        @DefaultCodable<EmptyString> var uuDeviceID: String
        @DefaultCodable<EmptyString> var uuDeviceAlias: String
        @DefaultCodable<EmptyString> var uuAnonymousDeviceID: String
        @DefaultCodable<EmptyString> var uuAssistID: String
        @DefaultCodable<EmptyString> var uuAssistCode: String
        @DefaultCodable<Zero> var uuDisplayID: Int
        @DefaultCodable<Sixty> var uuFPS: Int
        @DefaultCodable<Five> var uuQuality: Int
        @DefaultFalse var uuTrueColor: Bool
        @DefaultFalse var uuManaged: Bool
        var ghosttyTerminfoVersion: String?
        var proxyJumpMachineID: String?

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

        var folder: RDFolder {
            switch source {
            case .local: RDFolder(id: id, name: name)
            case let .uuRemote(userID): RDFolder(id: id, name: name, source: .uuRemote(userID: userID))
            }
        }
    }
}
