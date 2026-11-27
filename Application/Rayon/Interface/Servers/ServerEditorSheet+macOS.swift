//
//  ServerEditorSheet+macOS.swift
//  Rayon
//
//  New / Edit Server: Name; Connect through; Address + Port; the Cloudflare
//  Access service token when connecting through it; Identity + Group; SFTP
//  start folder; Comment; Last banner (read-only, captured on connect).
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    struct ServerEditorSheet: View {
        /// nil creates a new server.
        let machine: RDMachine.ID?
        /// What a new server starts from (a host found nearby); nothing is saved
        /// until Save.
        var template: RDMachine?
        var close: (() -> Void)?

        @EnvironmentObject var store: RayonStore
        @Environment(\.dismiss) private var dismiss

        @State private var draft = ServerDraft()
        @State private var banner = ""

        @ObservedObject private var uuAccount = UURemoteAccount.shared

        @State private var connecting = false
        @State private var error: String?
        @State private var showsUURemoteAccount = false
        @State private var picksIdentity = false

        var isNew: Bool { machine == nil }
        var canSave: Bool { draft.isValid }

        var jumpServerChoices: [RayonStore.JumpServerChoice] {
            store.jumpServerChoices(for: machine)
        }

        var existingGroups: [String] {
            Set(store.folders.map(\.name))
                .filter { !$0.isEmpty }
                .sorted()
        }

        var body: some View {
            SheetScaffold(isNew ? "New Server" : "Edit Server") {
                ScrollView(.vertical, showsIndicators: true) {
                    fields
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                // Next to the buttons, not at the end of the scrolled fields,
                // where a failed Add and Connect would go unseen.
                if let error {
                    HelpText(error, isError: true)
                        .padding(.top, RX.Space.s3)
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
                    Button("Add", action: saveWithoutConnecting)
                        .buttonStyle(.rx)
                        .disabled(!canSave || connecting)
                        .help("Save the server without connecting")
                    Button("Add and Connect", action: createAndConnect)
                        .buttonStyle(.rxPrimary)
                        .help("Check the connection, then save the server")
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
            .sheet(isPresented: $showsUURemoteAccount) {
                UURemoteAccountSheet(onConnectDesktop: { machineID in
                    showsUURemoteAccount = false
                    AppRouter.shared.openDesktop(machine: machineID)
                }, close: { showsUURemoteAccount = false })
            }
            .sheet(isPresented: $picksIdentity) {
                IdentityPickerSheet { picked in
                    picksIdentity = false
                    guard let picked else { return }
                    draft.identity = picked
                    createAndConnect()
                }
            }
        }

        private var fields: some View {
            VStack(alignment: .leading, spacing: 14) {
                RXField("Name") {
                    TextField(draft.address.isEmpty ? "prod-web-01" : draft.address, text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                RXField("Connect through") {
                    Picker("Connect through", selection: $draft.transport) {
                        Text("Direct (TCP)").tag(RDMachine.Transport.direct)
                        Text("ProxyJump (Bastion)").tag(RDMachine.Transport.proxyJump)
                        Text("Cloudflare Access").tag(RDMachine.Transport.cloudflareAccess)
                        Text("NetEase UU Remote").tag(RDMachine.Transport.uuRemote)
                    }
                    .labelsHidden()
                }
                if draft.transport == .proxyJump {
                    RXField("Jump server (Bastion)", help: "Reaches this server through an SSH tunnel opened on the jump server (ssh -J).") {
                        // A menu rather than a Picker: a Picker's items cannot be
                        // disabled on macOS, and the unavailable ones are shown.
                        let choices = jumpServerChoices
                        Menu {
                            ForEach(choices) { choice in
                                Toggle(choice.title, isOn: Binding(
                                    get: { draft.proxyJumpMachineID == choice.id },
                                    set: { _ in draft.proxyJumpMachineID = choice.id }
                                ))
                                .disabled(choice.unavailableReason != nil)
                            }
                        } label: {
                            Text(choices.first { $0.id == draft.proxyJumpMachineID }?.title
                                ?? (choices.isEmpty ? "No other SSH servers saved" : "Choose a jump server…"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField(draft.transport == .cloudflareAccess ? "Access hostname" : draft.transport == .uuRemote ? "Device ID" : "Address") {
                        TextField(draft.transport == .cloudflareAccess ? "ssh.example.com" : draft.transport == .uuRemote ? "UU Remote device id" : "Host name or IP address", text: $draft.address)
                            .textFieldStyle(.roundedBorder)
                            .font(.rxCode)
                            .disableAutocorrection(true)
                    }
                    RXField("Port", error: draft.portIsValid ? nil : "1–65535") {
                        TextField("22", text: $draft.port)
                            .textFieldStyle(.roundedBorder)
                            .font(.rxCode)
                    }
                    .frame(width: 96)
                }
                if draft.transport == .cloudflareAccess {
                    cloudflareFields
                } else if draft.transport == .uuRemote {
                    HelpText("Files, Monitor and the editor reach the device's own SSH server through UU Remote, signed in with the identity below; on a Mac, turn on System Settings › General › Sharing › Remote Login. The terminal is UU Remote's own and needs neither.")
                }
                RXField("Remote Desktop") {
                    Picker("Remote Desktop", selection: $draft.remoteDesktopProtocol) {
                        Text("None").tag(RDMachine.RemoteDesktopProtocolType.none)
                        Text("VNC").tag(RDMachine.RemoteDesktopProtocolType.vnc)
                        Text("NetEase UU Remote").tag(RDMachine.RemoteDesktopProtocolType.uuRemote)
                    }
                    .labelsHidden()
                }
                if draft.remoteDesktopProtocol == .vnc {
                    vncFields
                } else if draft.remoteDesktopProtocol == .uuRemote {
                    uuFields
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Identity") {
                        Picker("Identity", selection: $draft.identity) {
                            Text("Automatic").tag(RDIdentity.ID?.none)
                            // An identity deleted since: a tagged row, or the Picker draws blank.
                            if let missing = draft.identity, store.identity(missing) == nil {
                                Text("Choose…").tag(RDIdentity.ID?.some(missing))
                            }
                            ForEach(store.identities) { item in
                                Text(item.group.isEmpty ? item.username : "\(item.username) · \(item.group)")
                                    .tag(RDIdentity.ID?.some(item.id))
                            }
                        }
                        .labelsHidden()
                    }
                    RXField("User name") {
                        TextField(sshUsernamePlaceholder, text: $draft.sshUsername)
                            .textFieldStyle(.roundedBorder)
                            .font(.rxCode)
                            .disableAutocorrection(true)
                    }
                }
                HelpText("The user name to sign in as on this server. It overrides the identity's, so one key can sign in as different users on different servers.")
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Group") {
                        HStack(spacing: RX.Space.s1) {
                            TextField("Default", text: $draft.folder)
                                .textFieldStyle(.roundedBorder)
                            if !existingGroups.isEmpty {
                                Menu {
                                    ForEach(existingGroups, id: \.self) { item in
                                        Button(item) { draft.folder = item }
                                    }
                                } label: {
                                    Label("Existing Groups", systemImage: "chevron.down")
                                        .labelStyle(.iconOnly)
                                }
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .help("Existing Groups")
                            }
                        }
                    }
                }
                RXField("SFTP start folder") {
                    TextField("/", text: $draft.startFolder)
                        .textFieldStyle(.roundedBorder)
                        .font(.rxCode)
                        .disableAutocorrection(true)
                }
                RXField("Comment") {
                    TextField("Optional", text: $draft.comment)
                        .textFieldStyle(.roundedBorder)
                }
                if !isNew {
                    RXField("Last banner") {
                        RXValueField(banner, placeholder: "None", monospaced: true)
                    }
                }
            }
        }

        /// The VNC listener details; reach it over an SSH local forward when
        /// the port only listens on the remote loopback.
        @ViewBuilder var vncFields: some View {
            HStack(alignment: .top, spacing: RX.Space.s4) {
                RXField("VNC port", error: draft.vncPortIsValid ? nil : "1–65535") {
                    TextField("5900", text: $draft.vncPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.rxCode)
                }
                RXField("VNC password") {
                    SecureField("Use identity password", text: $draft.vncPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
            RXField("Mac user name") {
                TextField("Use identity user name", text: $draft.vncUsername)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            HelpText("macOS Screen Sharing signs in with a Mac user name and password. Leave the VNC password empty to use the identity's; a VNC password alone uses VNC authentication.")
            HStack(spacing: RX.Space.s5) {
                Toggle("Tunnel over SSH", isOn: $draft.vncOverSSH)
                Toggle("Shared session", isOn: $draft.vncShared)
            }
            .toggleStyle(.switch)
        }

        /// Which UU Remote device draws the screen — pick one off the signed-in
        /// account or paste an id, or leave it to an assist code.
        @ViewBuilder var uuFields: some View {
            if !uuAccount.isLoggedIn {
                HelpText("Sign in to a UU Remote account to pick a device, or paste a device id / assist code below.")
            }
            if !uuAccount.desktopDevices.isEmpty {
                RXField("UU Remote device") {
                    Picker("UU Remote device", selection: $draft.uuDeviceID) {
                        Text("Manual / assist").tag("")
                        // A device no longer on the account: a tagged row, or the Picker draws blank.
                        if !draft.uuDeviceID.isEmpty, !uuAccount.desktopDevices.contains(where: { $0.deviceID == draft.uuDeviceID }) {
                            Text("\(draft.uuDeviceID) · not on this account").tag(draft.uuDeviceID)
                        }
                        ForEach(uuAccount.desktopDevices, id: \.deviceID) { device in
                            Text("\(device.alias.isEmpty ? device.deviceID : device.alias) · \(UUDeviceInfo.platformName(device.platform))")
                                .tag(device.deviceID)
                        }
                    }
                    .labelsHidden()
                }
            }
            if draft.uuDeviceID.isEmpty {
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Device ID") {
                        TextField("From the account's device list", text: $draft.uuDeviceID)
                            .textFieldStyle(.roundedBorder)
                            .font(.rxCode)
                            .disableAutocorrection(true)
                    }
                }
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    RXField("Assist connect ID") {
                        TextField("Optional", text: $draft.uuAssistID)
                            .textFieldStyle(.roundedBorder)
                            .font(.rxCode)
                            .disableAutocorrection(true)
                    }
                    RXField("Assist code") {
                        SecureField("Optional", text: $draft.uuAssistCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.rxCode)
                    }
                }
            }
            HStack {
                Button("UU Remote Account & Devices…") {
                    showsUURemoteAccount = true
                }
                .buttonStyle(.rx)
                if uuAccount.isLoggedIn {
                    Text(UURemoteAccount.deviceCount(uuAccount.desktopDevices.count))
                        .font(.rxCaption)
                        .foregroundStyle(.rxInkSecondary)
                }
            }
        }

        /// What `cloudflared access ssh` would send: nothing for an application
        /// without an Access policy, a service token for one that asks for it.
        @ViewBuilder var cloudflareFields: some View {
            HStack(alignment: .top, spacing: RX.Space.s4) {
                RXField("Service token Client ID") {
                    TextField("Optional", text: $draft.serviceTokenID)
                        .textFieldStyle(.roundedBorder)
                        .font(.rxCode)
                        .disableAutocorrection(true)
                }
                RXField("Client Secret") {
                    SecureField("Optional", text: $draft.serviceTokenSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.rxCode)
                }
            }
            HelpText("Connects like ssh -o ProxyCommand='cloudflared access ssh --hostname %h', without cloudflared. Leave the service token empty when the application has no Access policy. The port only names the server's host key.")
        }

        /// The identity's user name, which applies while the field is empty.
        var sshUsernamePlaceholder: String {
            guard let identity = draft.identity else { return "Use identity user name" }
            let username = (store.identity(identity) ?? RDIdentity()).username
            return username.isEmpty ? "Use identity user name" : "\(username) (from identity)"
        }

        func load() {
            guard let read = machine.flatMap({ store.machine($0) }) ?? template else { return }
            draft = ServerDraft(read, folder: store.folderName(of: read))
            banner = read.lastBanner
        }

        func finish() {
            if let close { close() } else { dismiss() }
        }

        /// Saves the server; nil, with `error` saying why, when it is refused.
        @discardableResult
        func save(banner capturedBanner: String? = nil, identity resolvedIdentity: RDIdentity.ID? = nil) -> RDMachine? {
            // A new server has never been connected to; RXFormat shows the epoch as "Never".
            let saved = machine.flatMap { store.machine($0) } ?? RDMachine(lastConnection: Date(timeIntervalSince1970: 0))
            var edited = draft
            if let resolvedIdentity { edited.identity = resolvedIdentity }
            var target = edited.apply(to: saved, folderId: store.folderId(forName: draft.folder))
            if let capturedBanner {
                target.lastBanner = capturedBanner
                target.lastConnection = Date()
            }
            guard store.save(target) else {
                error = store.problem(saving: target)?.localizedDescription ?? "The server could not be saved."
                return nil
            }
            return target
        }

        func saveWithoutConnecting() {
            guard save() != nil else { return }
            finish()
        }

        /// Connects first; when no identity authenticates, asks for one.
        func createAndConnect() {
            error = nil
            connecting = true
            let host = draft.trimmedAddress
            let port = draft.port
            let checked = draft.apply(to: RDMachine(), folderId: nil)
            let chosen = draft.identity.flatMap { store.identity($0) }
            let candidates = store.identitiesForAutoAuth
            let timeout = NSNumber(value: AppSettings.connectionTimeout.value)
            Task {
                let outcome = await ServerConnectionCheck.run(checked, identity: chosen, candidates: candidates, timeout: timeout)
                connecting = false
                if case let .unreachable(refusal) = outcome {
                    error = refusal ?? "Could not reach \(host) on port \(port)."
                } else if case let .authenticated(authenticatedWith, banner) = outcome {
                    finishCreation(banner: banner, identity: authenticatedWith)
                } else if chosen != nil {
                    error = "The selected identity could not sign in to \(host)."
                } else {
                    error = "No identity that authenticates automatically could sign in. Choose an identity."
                    picksIdentity = true
                }
            }
        }

        func finishCreation(banner: String, identity: RDIdentity.ID) {
            guard let created = save(banner: banner, identity: identity) else { return }
            finish()
            AppRouter.shared.openTerminal(machine: created.id)
        }
    }

#endif
