//
//  IdentityEditor.swift
//  Rayon
//
//  New / Edit Identity: Username, Group; Key pair (load, paste or generate
//  an Ed25519 pair; public key; passphrase), Password (shown after the
//  device's owner confirms) or SSH Agent; Authenticate automatically;
//  Comment. An existing identity can deploy its public key (ssh-copy-id).
//

import RayonModule
import SwiftUI
import UniformTypeIdentifiers

struct IdentityEditor: View {
    /// nil creates a new identity.
    let identity: RDIdentity.ID?
    var onSaved: ((RDIdentity.ID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    private let original: RDIdentity
    @State private var draft: IdentityDraft
    @State private var showsPassword = false
    /// Which key the file importer is loading.
    @State private var importing: KeyKind?

    private enum KeyKind {
        case privateKey
        case publicKey
    }

    init(identity: RDIdentity.ID?, onSaved: ((RDIdentity.ID) -> Void)? = nil) {
        self.identity = identity
        self.onSaved = onSaved
        let read = identity.flatMap { RayonStore.shared.identity($0) }
            ?? RDIdentity(lastRecentUsed: Date(timeIntervalSince1970: 0))
        original = read
        _draft = State(initialValue: IdentityDraft(read))
    }

    private var isNew: Bool { identity == nil }

    /// SSH Agent signs in through the Mac's agent; elsewhere it is offered
    /// only to keep an identity that already uses it, say one synced from a
    /// Mac.
    private var offersSSHAgent: Bool {
        #if os(macOS)
            true
        #else
            original.useSSHAgent
        #endif
    }

    private var trimmedPublicKey: String {
        draft.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                FormField("Username", text: $draft.username, prompt: Text("root"), code: true)
                FormField("Group", text: $draft.group, prompt: Text("Default"))
            }
            Section {
                Picker("Authentication", selection: $draft.method) {
                    Text("Key pair").tag(IdentityDraft.Method.keyPair)
                    Text("Password").tag(IdentityDraft.Method.password)
                    if offersSSHAgent {
                        Text("SSH Agent").tag(IdentityDraft.Method.sshAgent)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                if draft.method == .sshAgent {
                    #if os(macOS)
                        Text("Signs in using your Mac's running SSH agent (SSH_AUTH_SOCK), including the system ssh-agent, 1Password SSH Agent, Secretive, or YubiKey/GPG agents.")
                    #else
                        Text("Signs in using the Mac's running SSH agent (SSH_AUTH_SOCK). iPhone and iPad have no SSH agent, so this identity signs in only from Rayon on a Mac.")
                    #endif
                }
            }
            switch draft.method {
            case .keyPair: keyPairSections
            case .password: passwordSection
            case .sshAgent: EmptyView()
            }
            Section {
                Toggle("Authenticate automatically", isOn: $draft.automatic)
            } footer: {
                Text("Required for Quick Connect.")
            }
            Section {
                FormField("Comment", text: $draft.comment, prompt: Text("Optional"))
            }
            if let identity {
                Section {
                    if draft.method == .keyPair, !trimmedPublicKey.isEmpty {
                        Button("Deploy Public Key (ssh-copy-id)…", systemImage: "square.and.arrow.up.on.square") {
                            IdentityActions.deployPublicKey(draft.publicKey, identityID: identity)
                        }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        IdentityActions.duplicate(identity)
                        dismiss()
                    }
                } footer: {
                    if draft.method == .keyPair, !trimmedPublicKey.isEmpty {
                        Text("Deploying appends the public key to ~/.ssh/authorized_keys on the servers you choose.")
                    }
                }
                Section {
                    Button("Delete Identity", systemImage: "trash", role: .destructive) {
                        IdentityActions.delete([identity]) { dismiss() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }), allowedContentTypes: [.item]) { result in
            guard let kind = importing, case let .success(url) = result else { return }
            load(url: url, as: kind)
        }
        .fileDialogDefaultDirectory(URL.homeDirectory.appending(path: ".ssh", directoryHint: .isDirectory))
        .fileDialogBrowserOptions(.includeHiddenFiles)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Save") {
                    let saved = draft.apply(to: original)
                    RayonStore.shared.save(saved)
                    onSaved?(saved.id)
                    dismiss()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!draft.isValid || !(isNew || draft.differs(from: original)))
            }
        }
        .editorSheet(isNew ? "New Identity" : "Edit Identity")
    }

    // MARK: - Key pair

    @ViewBuilder private var keyPairSections: some View {
        Section {
            Button("Import from File", systemImage: "square.and.arrow.down") { importing = .privateKey }
            Button("Import from Pasteboard", systemImage: "doc.on.clipboard") { load(Pasteboard.string, as: .privateKey) }
            Button("Generate Ed25519 Key Pair", systemImage: "key.horizontal", action: generateKeyPair)
                .help("Generate a new OpenSSH Ed25519 key pair in memory")
            Button("Clear Key Data", systemImage: "trash", role: .destructive) { draft.privateKey = "" }
                .disabled(draft.privateKey.isEmpty)
        } header: {
            Text("Private Key")
        } footer: {
            Text(privateKeyDescription)
        }
        Section {
            if !trimmedPublicKey.isEmpty {
                Text(trimmedPublicKey)
                    .font(.rxCode)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button("Copy Public Key", systemImage: "doc.on.doc") { Pasteboard.copy(trimmedPublicKey) }
                ShareLink(item: trimmedPublicKey + "\n") {
                    Label("Share Public Key", systemImage: "square.and.arrow.up")
                }
            }
            Button("Import from File", systemImage: "square.and.arrow.down") { importing = .publicKey }
            Button("Import from Pasteboard", systemImage: "doc.on.clipboard") { load(Pasteboard.string, as: .publicKey) }
            Button("Clear Key Data", systemImage: "trash", role: .destructive) { draft.publicKey = "" }
                .disabled(draft.publicKey.isEmpty)
        } header: {
            Text("Public Key")
        } footer: {
            Text(trimmedPublicKey.isEmpty ? "Optional. Needed to deploy the key to servers." : "\(draft.keyAlgorithmLabel ?? String(localized: "Public key"))")
        }
        Section {
            FormField("Passphrase", text: $draft.passphrase, prompt: Text("None"), secure: true)
        } footer: {
            Text("Unlocks the private key, when it has one.")
        }
    }

    private var privateKeyDescription: String {
        guard !draft.privateKey.isEmpty else { return String(localized: "Required for a key pair.") }
        let header = draft.privateKey.split(separator: "\n").first.map(String.init) ?? ""
        return String(localized: "\(header) · \(draft.privateKey.utf8.count) bytes")
    }

    private func generateKeyPair() {
        guard !draft.privateKey.isEmpty else { return draft.generateEd25519KeyPair() }
        Indicator.confirm(
            message: "Replace the key pair?",
            informative: "Servers that only accept the current key stop accepting this identity.",
            confirmTitle: "Replace",
            destructive: true
        ) { confirmed in
            if confirmed { draft.generateEd25519KeyPair() }
        }
    }

    // MARK: - Password

    private var passwordSection: some View {
        Section {
            FormField("Password", text: $draft.password, prompt: Text("Required"), secure: !showsPassword, code: showsPassword)
            if !draft.password.isEmpty {
                if showsPassword {
                    Button("Hide Password", systemImage: "eye.slash") { showsPassword = false }
                } else {
                    Button("Show Password", systemImage: "eye") {
                        Task { showsPassword = await DeviceOwner.confirm("show the identity's password") }
                    }
                }
            }
        }
    }

    // MARK: - Loading keys

    private func load(url: URL, as kind: KeyKind) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            Indicator.error(String(localized: "The file could not be read as text."))
            return
        }
        load(text, as: kind)
    }

    /// Loads the key, asking first when it does not look like one.
    private func load(_ text: String?, as kind: KeyKind) {
        guard let text, !text.isEmpty else {
            Indicator.error(String(localized: "Unable to read"))
            return
        }
        let isPrivate = kind == .privateKey
        let apply = {
            if isPrivate { draft.privateKey = text } else { draft.publicKey = text }
        }
        if isPrivate ? RDIdentity.looksLikePrivateKey(text) : RDIdentity.looksLikePublicKey(text) {
            apply()
        } else {
            Indicator.confirm(
                message: isPrivate ? "This does not look like a private key" : "This does not look like a public key",
                informative: "Load it anyway?",
                confirmTitle: "Load"
            ) { confirmed in
                if confirmed { apply() }
            }
        }
    }
}

private extension IdentityDraft {
    /// "ed25519 public key" style line for the key in the draft.
    var keyAlgorithmLabel: String? {
        var probe = RDIdentity()
        probe.publicKey = publicKey
        probe.privateKey = privateKey
        return probe.keyAlgorithm.map { String(localized: "\($0) public key") }
    }
}
