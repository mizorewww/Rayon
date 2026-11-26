//
//  RayonStore+Server.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/1.
//

import Foundation

public extension RayonStore {
    /// The saved server an alias names, as `ssh myserver` names a Host in
    /// ~/.ssh/config: the first whose name matches, ignoring case, else the
    /// first whose address does. Nil when none does.
    func machine(matchingAlias alias: String) -> RDMachine? {
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return nil }
        let saved = machines.filter(\.hasAddress)
        func matches(_ value: String) -> Bool {
            value.caseInsensitiveCompare(alias) == .orderedSame
        }
        return saved.first { matches($0.name) } ?? saved.first { matches($0.remoteAddress) }
    }

    /// The saved server Quick Connect input names: `myserver` or
    /// `ssh myserver`. Nil when the input is not a lone alias or no saved
    /// server matches it.
    func machine(matchingQuickConnect input: String) -> RDMachine? {
        SSHCommandReader.quickConnectAlias(input).flatMap { machine(matchingAlias: $0) }
    }

    func findSimilarMachine(
        withAddr: String,
        withPort: String,
        withUsername: String?
    ) -> RDMachine.ID? {
        guard !withAddr.isEmpty, !withPort.isEmpty else { return nil }
        return machines.first { machine in
            guard machine.remoteAddress == withAddr, machine.remotePort == withPort else { return false }
            guard let withUsername else { return true }
            guard let identity = associatedIdentity(for: machine) else { return false }
            return machine.sshLoginUsername(identity: identity) == withUsername
        }?.id
    }

    /// Parses an OpenSSH `~/.ssh/config` text and imports any non-wildcard `Host` entries
    /// (along with referenced `IdentityFile` keys and `ProxyJump` links).
    /// `keyDirectory` is where to look for a key, by its file name, when its
    /// path cannot be read: on iOS, the `.ssh` folder the person picked, since
    /// the home folder there is the app's own container.
    @MainActor
    @discardableResult
    func importOpenSSHConfig(_ text: String, baseDirectory: URL? = nil, keyDirectory: URL? = nil) -> (importedServers: Int, importedIdentities: Int) {
        struct RawHostBlock {
            var aliases: [String] = []
            var hostName: String?
            var user: String?
            var port: String?
            var identityFile: String?
            var proxyJump: String?
        }

        var blocks: [RawHostBlock] = []
        var current: RawHostBlock?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            if key == "host" {
                if let current { blocks.append(current) }
                let aliases = value.split(whereSeparator: \.isWhitespace).map(String.init).filter {
                    !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!")
                }
                current = RawHostBlock(aliases: aliases)
            } else if current != nil {
                switch key {
                case "hostname": current?.hostName = value
                case "user": current?.user = value
                case "port": current?.port = value
                case "identityfile": if current?.identityFile == nil { current?.identityFile = value }
                case "proxyjump": current?.proxyJump = value
                default: break
                }
            }
        }
        if let current { blocks.append(current) }

        var importedServers = 0
        var importedIdentities = 0
        var aliasToMachineID: [String: UUID] = [:]
        var pendingProxyJump: [(machineID: UUID, jumpAlias: String)] = []

        var newMachines: [RDMachine] = []
        var knownIdentities = identities
        let existingConfigFolder = folder(named: "SSH Config")
        let sshConfigFolder = existingConfigFolder ?? createFolder(named: "SSH Config")

        for block in blocks {
            for alias in block.aliases {
                let host = block.hostName ?? alias
                let port = block.port ?? "22"
                guard !host.isEmpty else { continue }

                var associatedIdentityID: RDIdentity.ID?
                if let username = block.user, !username.isEmpty {
                    var loadedPriv = ""
                    var loadedPub = ""
                    if let idFile = block.identityFile {
                        let expanded = (idFile as NSString).expandingTildeInPath
                        let fileURL: URL
                        if expanded.hasPrefix("/") {
                            fileURL = URL(fileURLWithPath: expanded)
                        } else if let baseDirectory {
                            fileURL = baseDirectory.appendingPathComponent(expanded)
                        } else {
                            fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh").appendingPathComponent(expanded)
                        }
                        var keyURL = fileURL
                        if let keyDirectory, !FileManager.default.isReadableFile(atPath: keyURL.path) {
                            keyURL = keyDirectory.appendingPathComponent(fileURL.lastPathComponent)
                        }
                        if let priv = try? String(contentsOf: keyURL, encoding: .utf8), RDIdentity.looksLikePrivateKey(priv) {
                            loadedPriv = priv
                            let pubURL = URL(fileURLWithPath: keyURL.path + ".pub")
                            if let pub = try? String(contentsOf: pubURL, encoding: .utf8) {
                                loadedPub = pub
                            }
                        }
                    }

                    // One identity per key: the user name belongs to the
                    // server, so hosts that share a key as different users
                    // share the identity. Without a key, an identity of
                    // the same user name is reused, else an SSH agent one.
                    let existing: RDIdentity? = if !loadedPriv.isEmpty {
                        knownIdentities.first(where: { $0.privateKey == loadedPriv })
                    } else {
                        knownIdentities.first(where: { $0.username == username })
                            ?? knownIdentities.first(where: { $0.useSSHAgent && $0.group == "SSH Config" })
                    }
                    if let existing {
                        associatedIdentityID = existing.id
                    } else {
                        var newIdentity = RDIdentity(
                            username: username,
                            privateKey: loadedPriv,
                            publicKey: loadedPub,
                            comment: "Imported from ssh_config (\(alias))",
                            group: "SSH Config"
                        )
                        if loadedPriv.isEmpty {
                            newIdentity.useSSHAgent = true
                        }
                        save(newIdentity)
                        knownIdentities.append(newIdentity)
                        associatedIdentityID = newIdentity.id
                        importedIdentities += 1
                    }
                }

                if let existingMachine = (machines + newMachines).first(where: { $0.name == alias || ($0.remoteAddress == host && $0.remotePort == port && $0.name == alias) }) {
                    aliasToMachineID[alias] = existingMachine.id
                    continue
                }

                let machine = RDMachine(
                    remoteAddress: host,
                    remotePort: port,
                    name: alias,
                    folderId: sshConfigFolder.id,
                    lastConnection: Date(timeIntervalSince1970: 0),
                    comment: "Imported from ~/.ssh/config",
                    associatedIdentity: associatedIdentityID,
                    sshUsername: block.user ?? ""
                )
                newMachines.append(machine)
                aliasToMachineID[alias] = machine.id
                if let jump = block.proxyJump, !jump.isEmpty, jump.lowercased() != "none" {
                    let firstJump = jump.split(separator: ",").first.map(String.init) ?? jump
                    pendingProxyJump.append((machine.id, firstJump.trimmingCharacters(in: .whitespaces)))
                }
                importedServers += 1
            }
        }

        for (machineID, jumpAlias) in pendingProxyJump {
            let resolvedJumpID = aliasToMachineID[jumpAlias]
                ?? (machines + newMachines).first(where: { $0.name == jumpAlias || $0.remoteAddress == jumpAlias })?.id
            if let resolvedJumpID, resolvedJumpID != machineID,
               let index = newMachines.firstIndex(where: { $0.id == machineID })
            {
                newMachines[index].transport = .proxyJump
                newMachines[index].proxyJumpMachineID = resolvedJumpID
            }
        }

        for machine in newMachines {
            save(machine)
        }
        if existingConfigFolder == nil, newMachines.isEmpty {
            deleteFolder(sshConfigFolder.id)
        }
        return (importedServers, importedIdentities)
    }
}
