//
//  ServerEditorSheet.swift
//  Rayon (macOS)
//
//  New / Edit Server: Name; Address + Port; Identity + Group; SFTP start folder;
//  Comment; Last banner (read-only, captured on connect).
//

import NSRemoteShell
import RayonModule
import SwiftUI

struct ServerEditorSheet: View {
    /// nil creates a new server.
    let machine: RDMachine.ID?
    var close: (() -> Void)?

    @EnvironmentObject var store: RayonStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var port = "22"
    @State private var identity: RDIdentity.ID?
    @State private var group = ""
    @State private var startFolder = "/"
    @State private var comment = ""
    @State private var banner = ""

    @State private var connecting = false
    @State private var error: String?

    var isNew: Bool { machine == nil }
    var portIsValid: Bool { UInt16(port) != nil }
    var canSave: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty && portIsValid }

    var existingGroups: [String] {
        Set(store.machineGroup.machines.map(\.group)).filter { !$0.isEmpty }.sorted()
    }

    var body: some View {
        SheetScaffold(isNew ? "New Server" : "Edit Server") {
            VStack(alignment: .leading, spacing: 14) {
                RXField("Name") {
                    TextField(address.isEmpty ? "prod-web-01" : address, text: $name)
                        .textFieldStyle(.rx)
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Address") {
                        TextField("Host name or IP address", text: $address)
                            .textFieldStyle(.rxMono)
                            .disableAutocorrection(true)
                    }
                    RXField("Port", error: portIsValid ? nil : "1–65535") {
                        TextField("22", text: $port)
                            .textFieldStyle(.rxMono)
                    }
                    .frame(width: 96)
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Identity") {
                        RXPicker(
                            selection: $identity,
                            options: [.init(nil, "Automatic")] + store.identityGroup.identities.map { item in
                                .init(item.id, item.group.isEmpty ? item.username : "\(item.username) · \(item.group)")
                            }
                        )
                    }
                    RXField("Group") {
                        HStack(spacing: RX.Space.s1) {
                            TextField("Default", text: $group)
                                .textFieldStyle(.rx)
                            if !existingGroups.isEmpty {
                                Menu {
                                    ForEach(existingGroups, id: \.self) { item in
                                        Button(item) { group = item }
                                    }
                                } label: {
                                    Label("Existing Groups", systemImage: "chevron.down")
                                }
                                .menuStyle(.button)
                                .menuIndicator(.hidden)
                                .buttonStyle(.rx(iconOnly: true))
                                .fixedSize()
                                .help("Choose an existing group")
                            }
                        }
                    }
                }
                RXField("SFTP start folder") {
                    TextField("/", text: $startFolder)
                        .textFieldStyle(.rxMono)
                        .disableAutocorrection(true)
                }
                RXField("Comment") {
                    TextField("Optional", text: $comment)
                        .textFieldStyle(.rx)
                }
                if !isNew {
                    RXField("Last banner") {
                        RXValueField(banner, placeholder: "None", monospaced: true)
                    }
                }
                if let error {
                    HelpText(error, isError: true)
                }
            }
        } footer: {
            Button("Cancel", action: finish)
                .buttonStyle(.rx)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if connecting {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
                    .font(.rxBody)
                    .foregroundStyle(.rxInkSecondary)
            }
            if isNew {
                Button("Create Without Connecting", action: saveWithoutConnecting)
                    .buttonStyle(.rx)
                    .disabled(!canSave || connecting)
                Button("Create and Connect", action: createAndConnect)
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || connecting)
            } else {
                Button("Save", action: saveWithoutConnecting)
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .frame(width: 520)
        .onAppear(perform: load)
    }

    func load() {
        guard let machine else { return }
        let read = store.machineGroup[machine]
        name = read.name
        address = read.remoteAddress
        port = read.remotePort
        group = read.group
        comment = read.comment
        startFolder = read.fileTransferLoginPath
        banner = read.lastBanner
        if let aid = read.associatedIdentity, let uid = UUID(uuidString: aid) {
            identity = uid
        }
    }

    func finish() {
        if let close { close() } else { dismiss() }
    }

    @discardableResult
    func save(banner capturedBanner: String? = nil, identity resolvedIdentity: RDIdentity.ID? = nil) -> RDMachine {
        // A new server has never been connected to; RXFormat shows the epoch as "Never".
        var target = machine.map { store.machineGroup[$0] } ?? RDMachine(lastConnection: Date(timeIntervalSince1970: 0))
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        target.remoteAddress = trimmedAddress
        target.remotePort = port
        target.name = name.isEmpty ? trimmedAddress : name
        target.group = group
        target.comment = comment
        target.fileTransferLoginPath = startFolder.isEmpty ? "/" : startFolder
        target.associatedIdentity = (resolvedIdentity ?? identity)?.uuidString
        if let capturedBanner {
            target.lastBanner = capturedBanner
            target.lastConnection = Date()
        }
        store.machineGroup.insert(target)
        return target
    }

    func saveWithoutConnecting() {
        save()
        finish()
    }

    /// Connects first; when no identity authenticates, asks for one.
    func createAndConnect() {
        error = nil
        connecting = true
        let host = address.trimmingCharacters(in: .whitespaces)
        let port = port
        let chosen = identity.map { store.identityGroup[$0] }
        let candidates = store.identityGroupForAutoAuth
        DispatchQueue.global().async {
            let shell = NSRemoteShell.configured(host: host, port: port, timeout: RayonStore.shared.timeoutNumber)
            shell.requestConnectAndWait()
            guard shell.isConnected else {
                onMainThread {
                    connecting = false
                    error = "Could not reach \(host) on port \(port)."
                }
                return
            }
            var authenticatedWith: RDIdentity.ID?
            if let chosen {
                chosen.callAuthenticationWith(remote: shell)
                if shell.isAuthenticated { authenticatedWith = chosen.id }
            } else {
                for candidate in candidates {
                    if shell.isAuthenticated { break }
                    if !shell.isConnected { shell.requestConnectAndWait() }
                    candidate.callAuthenticationWith(remote: shell)
                    if shell.isAuthenticated { authenticatedWith = candidate.id }
                }
            }
            let banner = shell.remoteBanner ?? ""
            shell.requestDisconnectAndWait()
            onMainThread {
                connecting = false
                if let authenticatedWith {
                    finishCreation(banner: banner, identity: authenticatedWith)
                } else if chosen != nil {
                    error = "The selected identity could not sign in to \(host)."
                } else {
                    error = "No identity that authenticates automatically could sign in. Choose an identity."
                    IdentityPickerPanel.present { picked in
                        guard let picked else { return }
                        identity = picked
                        createAndConnect()
                    }
                }
            }
        }
    }

    func finishCreation(banner: String, identity: RDIdentity.ID) {
        let created = save(banner: banner, identity: identity)
        finish()
        onMainThread(delay: 0.2) {
            AppRouter.shared.openTerminal(machine: created.id)
        }
    }
}
