//
//  IdentitiesView.swift
//  Rayon (macOS)
//
//  Identities grouped by group, with the editor beside the list.
//

import RayonModule
import SwiftUI

struct IdentitiesView: View {
    @EnvironmentObject var store: RayonStore

    @State private var searchText = ""
    @State private var selection: RDIdentity.ID?
    @State private var creating = false

    var filtered: [RDIdentity] {
        let all = store.identityGroup.identities
        guard !searchText.isEmpty else { return all }
        let key = searchText.lowercased()
        return all.filter {
            $0.username.lowercased().contains(key)
                || $0.group.lowercased().contains(key)
                || $0.comment.lowercased().contains(key)
        }
    }

    var groups: [(name: String, identities: [RDIdentity])] {
        let identities = filtered
        let names = Set(identities.map(\.group)).sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return names.map { name in
            (name, identities.filter { $0.group == name }.sorted { $0.username < $1.username })
        }
    }

    var subtitle: String {
        let count = store.identityGroup.count
        guard count > 0 else { return "Usernames with a password or key pair that Rayon signs in with." }
        let used = store.machineGroup.machines.filter { $0.associatedIdentity != nil }.count
        return "\(count) identit\(count == 1 ? "y" : "ies") · used by \(used) server\(used == 1 ? "" : "s")"
    }

    var body: some View {
        PageScaffold(search: $searchText, searchPrompt: "Search identities") {
        } trailing: {
            ToolbarAction("New Identity", systemImage: "plus", primary: true) { creating = true }
        } header: {
            PageTitle("Identities", subtitle: subtitle)
        } content: {
            if store.identityGroup.identities.isEmpty {
                EmptyStateView(
                    "No identities yet",
                    systemImage: "person",
                    message: "An identity is a username with a password or key pair. Servers and Quick Connect sign in with it.",
                    actionTitle: "New Identity"
                ) {
                    creating = true
                }
                .rxCard()
            } else {
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    list
                        .frame(width: 320)
                    if let selection, store.identityGroup.identities.contains(where: { $0.id == selection }) {
                        IdentityDetail(identity: selection)
                            .id(selection)
                    } else {
                        EmptyStateView(
                            "Select an identity",
                            systemImage: "person",
                            message: "Choose an identity on the left to see and edit it."
                        )
                        .rxCard()
                    }
                }
            }
        }
        .sheet(isPresented: $creating) {
            IdentityEditorSheet(identity: nil) { created in
                creating = false
                if let created { selection = created }
            }
        }
        .onAppear {
            if selection == nil { selection = groups.first?.identities.first?.id }
        }
    }

    var list: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                EmptyStateView("No matches", systemImage: "magnifyingglass", message: "No identity matches “\(searchText)”.")
            }
            ForEach(groups, id: \.name) { group in
                TableGroupRow(group.name.isEmpty ? "Default" : group.name)
                ForEach(group.identities) { identity in
                    IdentityRow(identity: identity, selected: selection == identity.id)
                        .onTapGesture { selection = identity.id }
                }
            }
        }
        .rxCard(padding: RX.Space.s2)
    }
}

private struct IdentityRow: View {
    let identity: RDIdentity
    let selected: Bool
    @EnvironmentObject var store: RayonStore
    @State private var hovered = false

    var usage: Int {
        store.machineGroup.machines.filter { $0.associatedIdentity == identity.id.uuidString }.count
    }

    var body: some View {
        HStack(spacing: RX.Space.s2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.username.isEmpty ? "No username" : identity.username)
                    .font(.rxBody)
                    .foregroundStyle(identity.username.isEmpty ? Color.rxInkSecondary : Color.rxInk)
                    .lineLimit(1)
                Text(identity.authDescription)
                    .font(.rxHelp)
                    .foregroundStyle(.rxInkSecondary)
            }
            Spacer()
            Text("\(usage) server\(usage == 1 ? "" : "s")")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.rxInkSecondary)
        }
        .padding(.horizontal, RX.Space.s3)
        .frame(height: RX.tableRowHeight)
        .rxRowBackground(selected: selected, hovered: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Duplicate") { IdentityActions.duplicate(identity.id) }
            Button("Copy Public Key") { UIBridge.sendPasteboard(str: identity.publicKey) }
                .disabled(identity.publicKey.isEmpty)
            Divider()
            Button("Delete…", role: .destructive) { IdentityActions.delete(identity.id) }
        }
    }
}

enum IdentityActions {
    static func duplicate(_ id: RDIdentity.ID) {
        var copy = RayonStore.shared.identityGroup[id]
        guard !copy.username.isEmpty else { return }
        copy.id = UUID()
        copy.comment = copy.comment.isEmpty ? "Copy" : copy.comment + " (copy)"
        RayonStore.shared.identityGroup.insert(copy)
    }

    static func delete(_ id: RDIdentity.ID) {
        let store = RayonStore.shared
        let identity = store.identityGroup[id]
        let users = store.machineGroup.machines.filter { $0.associatedIdentity == id.uuidString }.count
        UIBridge.requiresConfirmation(
            message: "Delete identity \(identity.username)?",
            informative: users > 0
                ? "\(users) server\(users == 1 ? "" : "s") use it and will try automatic identities instead."
                : "Its password and keys are removed from Rayon.",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            store.identityGroup.delete(id)
        }
    }
}

/// The editor beside the list.
private struct IdentityDetail: View {
    let identity: RDIdentity.ID
    @EnvironmentObject var store: RayonStore
    @State private var draft = IdentityDraft()
    @State private var loaded = false

    var original: RDIdentity { store.identityGroup[identity] }

    var usedBy: [String] {
        store.machineGroup.machines
            .filter { $0.associatedIdentity == identity.uuidString }
            .map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(original.username.isEmpty ? "No username" : original.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.rxInk)
                    HelpText(usageLine)
                }
                Spacer()
                Menu {
                    Button("Duplicate") { IdentityActions.duplicate(identity) }
                    Divider()
                    Button("Delete…", role: .destructive) { IdentityActions.delete(identity) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.rx(.plain, iconOnly: true))
                .fixedSize()
            }
            IdentityForm(draft: $draft)
                .padding(.top, RX.Space.s5)
            HStack(spacing: RX.Space.s2) {
                if draft.differs(from: original) {
                    HelpText("Unsaved changes")
                }
                Spacer()
                Button("Revert") { draft = IdentityDraft(original) }
                    .buttonStyle(.rx)
                    .disabled(!draft.differs(from: original))
                Button("Save") {
                    store.identityGroup.insert(draft.apply(to: original))
                }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!draft.differs(from: original) || !draft.isValid)
            }
            .padding(.top, RX.Space.s4)
        }
        .rxCard()
        .frame(maxWidth: .infinity)
        .onAppear {
            draft = IdentityDraft(original)
        }
        .onDisappear {
            // Keep edits when another identity is selected.
            let stillExists = store.identityGroup.identities.contains { $0.id == identity }
            if stillExists, draft.differs(from: original), draft.isValid {
                store.identityGroup.insert(draft.apply(to: original))
            }
        }
    }

    var usageLine: String {
        let names = usedBy
        let used = original.lastRecentUsed.timeIntervalSince1970 > 0
            ? " · last used \(RXFormat.relative(original.lastRecentUsed).lowercased())"
            : ""
        if names.isEmpty { return "Not used by any server" + used }
        let shown = names.prefix(4).joined(separator: ", ")
        let more = names.count > 4 ? " and \(names.count - 4) more" : ""
        return "Used by \(shown)\(more)\(used)"
    }
}

/// Editable copy of an identity.
struct IdentityDraft: Equatable {
    enum Method: Hashable {
        case keyPair
        case password
    }

    var username = ""
    var group = ""
    var method: Method = .password
    var password = ""
    var privateKey = ""
    var publicKey = ""
    var comment = ""
    var automatic = true

    init() {}

    init(_ identity: RDIdentity) {
        username = identity.username
        group = identity.group
        method = identity.privateKey.isEmpty ? .password : .keyPair
        password = identity.password
        privateKey = identity.privateKey
        publicKey = identity.publicKey
        comment = identity.comment
        automatic = identity.authenticAutomatically
    }

    var isValid: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty }

    func apply(to identity: RDIdentity) -> RDIdentity {
        var result = identity
        result.username = username.trimmingCharacters(in: .whitespaces)
        result.group = group
        result.password = password
        result.privateKey = method == .keyPair ? privateKey : ""
        result.publicKey = method == .keyPair ? publicKey : ""
        result.comment = comment
        result.authenticAutomatically = automatic
        return result
    }

    /// RDIdentity compares by id only, so compare the edited fields.
    func differs(from identity: RDIdentity) -> Bool {
        let edited = apply(to: identity)
        return edited.username != identity.username
            || edited.group != identity.group
            || edited.password != identity.password
            || edited.privateKey != identity.privateKey
            || edited.publicKey != identity.publicKey
            || edited.comment != identity.comment
            || edited.authenticAutomatically != identity.authenticAutomatically
    }
}

/// Username, Group, Key pair / Password, keys, Password, Comment, Authenticate automatically.
struct IdentityForm: View {
    @Binding var draft: IdentityDraft
    @EnvironmentObject var store: RayonStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: RX.Space.s4) {
                RXField("Username") {
                    TextField("root", text: $draft.username)
                        .textFieldStyle(.rx)
                        .disableAutocorrection(true)
                }
                RXField("Group") {
                    TextField("Default", text: $draft.group)
                        .textFieldStyle(.rx)
                }
            }
            RXField("Authentication") {
                RXSegmented(selection: $draft.method, options: [
                    .init(.keyPair, "Key pair"),
                    .init(.password, "Password"),
                ], caps: false, fullWidth: true)
            }
            if draft.method == .keyPair {
                RXField("Private key") {
                    KeyField(
                        text: $draft.privateKey,
                        masked: true,
                        placeholder: "No private key loaded",
                        loadTitle: "Load Private Key…",
                        expectation: "PRIVATE KEY"
                    )
                }
                RXField("Public key", help: "Optional. Some servers need it alongside the private key.") {
                    KeyField(
                        text: $draft.publicKey,
                        masked: false,
                        placeholder: "No public key loaded",
                        loadTitle: "Load Public Key…",
                        expectation: "ssh-"
                    )
                }
                RXField("Password (optional, unlocks the key)") {
                    SecureField("None", text: $draft.password)
                        .textFieldStyle(.rx)
                }
            } else {
                RXField("Password") {
                    SecureField("Password", text: $draft.password)
                        .textFieldStyle(.rx)
                }
            }
            RXField("Comment") {
                TextField("Optional", text: $draft.comment)
                    .textFieldStyle(.rx)
            }
            Hairline()
            SwitchRow(
                "Authenticate automatically",
                description: "Tried when a server has no identity set. Required for Quick Connect.",
                isOn: $draft.automatic
            )
        }
    }
}

/// A key shown in `code`, masked when private, with Load, Copy and Clear.
private struct KeyField: View {
    @Binding var text: String
    let masked: Bool
    let placeholder: String
    let loadTitle: String
    let expectation: String

    var display: String {
        guard !text.isEmpty else { return "" }
        let lines = text.split(separator: "\n").map(String.init)
        if masked {
            let header = lines.first ?? ""
            let bytes = text.utf8.count
            return "\(header)  •••••••• \(bytes) bytes"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: RX.Space.s2) {
            RXValueField(display, placeholder: placeholder, monospaced: true)
            if !text.isEmpty {
                if !masked {
                    RXIconButton("Copy", systemImage: "doc.on.doc") {
                        UIBridge.sendPasteboard(str: text)
                    }
                }
                RXIconButton("Remove", systemImage: "minus.circle") { text = "" }
            }
            Button(loadTitle) { load() }
                .buttonStyle(.rx)
        }
    }

    func load() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "\(NSHomeDirectory())/.ssh/")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .utf8) else {
                UIBridge.presentError(with: "The file could not be read as text.")
                return
            }
            if string.contains(expectation) {
                text = string
            } else {
                mainActor(delay: 0.3) {
                    UIBridge.requiresConfirmation(
                        message: "This file does not look like a \(masked ? "private" : "public") key",
                        informative: "Load it anyway?",
                        confirmTitle: "Load"
                    ) { confirmed in
                        if confirmed { text = string }
                    }
                }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }
}

/// New Identity as a sheet (from Identities and the identity picker).
struct IdentityEditorSheet: View {
    let identity: RDIdentity.ID?
    let onComplete: (RDIdentity.ID?) -> Void

    @EnvironmentObject var store: RayonStore
    @State private var draft = IdentityDraft()

    var body: some View {
        SheetScaffold(identity == nil ? "New Identity" : "Edit Identity", lead: "A username with a password or key pair.") {
            IdentityForm(draft: $draft)
        } footer: {
            Spacer()
            Button("Cancel") { onComplete(nil) }
                .buttonStyle(.rx)
                .keyboardShortcut(.cancelAction)
            Button(identity == nil ? "Create" : "Save") {
                var base = identity.map { store.identityGroup[$0] } ?? RDIdentity(
                    username: "",
                    password: "",
                    privateKey: "",
                    publicKey: "",
                    lastRecentUsed: .init(timeIntervalSince1970: 0),
                    comment: "",
                    group: "",
                    authenticAutomatically: true,
                    attachment: [:]
                )
                base = draft.apply(to: base)
                store.identityGroup.insert(base)
                onComplete(base.id)
            }
            .buttonStyle(.rxPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.isValid)
        }
        .frame(width: 520)
        .onAppear {
            if let identity { draft = IdentityDraft(store.identityGroup[identity]) }
        }
    }
}
