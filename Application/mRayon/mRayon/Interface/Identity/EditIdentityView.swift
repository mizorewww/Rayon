//
//  EditIdentityView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI

struct EditIdentityView: View {
    @Environment(\.dismiss) private var dismiss

    let inEditWith: (() -> (UUID?))?

    init(requestIdentity: (() -> (UUID?))? = nil) {
        inEditWith = requestIdentity
    }

    @State var initializedOnce = false

    @State var username: String = ""
    @State var password: String = ""
    @State var privateKey: String = ""
    @State var publicKey: String = ""
    @State var comment: String = ""
    @State var group: String = ""
    @State var autoAuth: Bool = true

    @State var showPassword = false

    var body: some View {
        List {
            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                RXSectionHeader("Username")
            } footer: {
                Text("Username is identical to the parameter used during ssh login.")
            }

            Section {
                if showPassword {
                    TextField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button {
                        showPassword = false
                    } label: {
                        Label("Hide Password", systemImage: "eye.slash")
                    }
                } else {
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button {
                        RayonUtil.deviceOwnershipAuthenticate { success in
                            if success { showPassword = true }
                        }
                    } label: {
                        Label("Show Password", systemImage: "eye")
                    }
                }
            } header: {
                RXSectionHeader("Password")
            } footer: {
                Text("Password is used to either authenticate the session or decrypt the private key. It's optional.")
            }

            Section {
                privateKeyButtons
            } header: {
                RXSectionHeader("Private Key")
            } footer: {
                Text(privateKeyDescription)
            }

            Section {
                publicKeyButtons
            } header: {
                RXSectionHeader("Public Key")
            } footer: {
                Text(publicKeyDescription)
            }

            Section {
                Toggle(isOn: $autoAuth) {
                    Text("Authenticate automatically")
                }
            } header: {
                RXSectionHeader("Automatic")
            } footer: {
                Text("Tried when a server has no identity set. Required for Quick Connect.")
            }

            Section {
                TextField("Comment (Optional)", text: $comment)
            } header: {
                RXSectionHeader("Comment")
            } footer: {
                Text("Comment does not take any effect in authenticate, but keep you remember this identity.")
            }

            Section {
                TextField("Default", text: $group)
                    .textInputAutocapitalization(.never)
            } header: {
                RXSectionHeader("Group")
            } footer: {
                Text("Items with the same group are listed together.")
            }
            if let identity = inEditWith?() {
                Section {
                    Button {
                        UIBridge.requiresConfirmation(
                            message: "Delete this identity?"
                        ) { confirmed in
                            if confirmed {
                                RayonStore.shared.identityGroup.delete(identity)
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Delete Identity", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            if initializedOnce { return }
            initializedOnce = true
            mainActor(delay: 0.1) { // <-- SwiftUI bug here, don't remove
                if let edit = inEditWith?() {
                    let read = RayonStore.shared.identityGroup[edit]
                    username = read.username
                    password = read.password
                    privateKey = read.privateKey
                    publicKey = read.publicKey
                    comment = read.comment
                    group = read.group
                    autoAuth = read.authenticAutomatically
                }
                if comment.isEmpty {
                    comment = "Created at: " + Date().formatted()
                }
            }
        }
        .rxGroupedList()
        .navigationTitle(inEditWith?() == nil ? "New Identity" : "Edit Identity")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    completeSheet()
                } label: {
                    Text("Save").bold()
                }
            }
        }
    }

    var privateKeyDescription: String {
        dataDescriptionFor(privateKey)
    }

    var publicKeyDescription: String {
        dataDescriptionFor(publicKey)
    }

    var privateKeyButtons: some View {
        Group {
            FilePicker(types: [.item], allowMultiple: false) { urls in
                guard let url = urls.first else {
                    return
                }
                loadPrivateKey(url: url)
            } label: {
                Label("Import from file", systemImage: "square.and.arrow.down.fill")
            }
            Button {
                loadPrivateKey(str: UIPasteboard.general.string)
            } label: {
                Label("Import from Pasteboard", systemImage: "doc.on.clipboard.fill")
            }
            Button {
                privateKey = ""
            } label: {
                Label("Clear Key Data", systemImage: "trash.fill")
            }
            .disabled(privateKey.isEmpty)
        }
    }

    var publicKeyButtons: some View {
        Group {
            FilePicker(types: [.item], allowMultiple: false) { urls in
                guard let url = urls.first else {
                    return
                }
                loadPublicKey(url: url)
            } label: {
                Label("Import from file", systemImage: "square.and.arrow.down.fill")
            }
            Button {
                loadPublicKey(str: UIPasteboard.general.string)
            } label: {
                Label("Import from Pasteboard", systemImage: "doc.on.clipboard.fill")
            }
            Button {
                publicKey = ""
            } label: {
                Label("Clear Key Data", systemImage: "trash.fill")
            }
            .disabled(publicKey.isEmpty)
        }
    }

    func loadPrivateKey(url: URL) {
        guard let data = try? String(contentsOfFile: url.path) else {
            UIBridge.presentError(with: "Unable to read")
            return
        }
        loadPrivateKey(str: data)
    }

    func loadPublicKey(url: URL) {
        guard let data = try? String(contentsOfFile: url.path) else {
            UIBridge.presentError(with: "Unable to read")
            return
        }
        loadPublicKey(str: data)
    }

    func loadPrivateKey(str: String?) {
        guard let str = str else {
            UIBridge.presentError(with: "Unable to read")
            return
        }
        if str.contains("PRIVATE KEY") {
            privateKey = str
        } else {
            UIBridge.requiresConfirmation(
                message: "File dose not look like a private key, still load the key?"
            ) { confirmed in
                if confirmed { privateKey = str }
            }
        }
    }

    func loadPublicKey(str: String?) {
        guard let str = str else {
            UIBridge.presentError(with: "Unable to read")
            return
        }
        if str.contains("ssh-") {
            publicKey = str
        } else {
            UIBridge.requiresConfirmation(
                message: "File dose not look like a public key, still load the key?"
            ) { confirmed in
                if confirmed { publicKey = str }
            }
        }
    }

    func dataDescriptionFor(_ str: String) -> String {
        if str.count > 0,
           let data = str.data(using: .utf8),
           data.count > 0
        {
            return "<\(data.count)> bytes"
        }
        return "No Data (Optional)"
    }

    func completeSheet() {
        guard !username.isEmpty else {
            UIBridge.presentError(with: "Empty Username")
            return
        }

        var id = UUID()
        if let inEditWith = inEditWith,
           let readId = inEditWith()
        {
            id = readId
        }

        let newIdentity = RDIdentity(
            id: id,
            username: username,
            password: password,
            privateKey: privateKey,
            publicKey: publicKey,
            lastRecentUsed: Date(timeIntervalSince1970: 0),
            comment: comment,
            group: group,
            authenticAutomatically: autoAuth,
            attachment: [:]
        )

        RayonStore.shared.identityGroup.insert(newIdentity)

        dismiss()
    }
}

struct EditIdentityView_Previews: PreviewProvider {
    static var previews: some View {
        createPreview {
            AnyView(EditIdentityView())
        }
    }
}
