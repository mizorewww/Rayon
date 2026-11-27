//
//  EditMachineView+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/3.
//
//  New / Edit Server: Name and Comment; Connect through (direct, a ProxyJump
//  bastion, Cloudflare Access or UU Remote); Address + Port; Remote Desktop;
//  Identity; Folder; SFTP start folder; Last banner (read-only). A new
//  server can be checked and connected before it is saved.
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    struct EditMachineView: View {
        @Environment(\.dismiss) private var dismiss

        let inEditWith: UUID?

        @State var draft: ServerDraft
        @State var openUUAccount = false
        @State var picksIdentity = false
        @ObservedObject var uuAccount = UURemoteAccount.shared

        /// What the server said last; shown, not edited.
        let banner: String

        @State var connecting = false
        @State var connectError: String?

        init(requestMachine: UUID? = nil) {
            inEditWith = requestMachine
            let read = requestMachine.flatMap { RayonStore.shared.machine($0) } ?? RDMachine()
            _draft = State(initialValue: ServerDraft(read, folder: RayonStore.shared.folderName(of: read)))
            banner = read.lastBanner
        }

        var isNew: Bool { inEditWith == nil }

        var canSave: Bool { draft.isValid }

        var jumpServerChoices: [RayonStore.JumpServerChoice] {
            RayonStore.shared.jumpServerChoices(for: inEditWith)
                .sorted { $0.machine.name.localizedStandardCompare($1.machine.name) == .orderedAscending }
        }

        var existingFolders: [String] {
            let store = RayonStore.shared
            return Set(store.folders.map(\.name))
                .filter { !$0.isEmpty }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        var identities: [RDIdentity] {
            RayonStore.shared.identities
                .sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
        }

        var body: some View {
            List {
                Section {
                    TextField(draft.trimmedAddress.isEmpty ? String(localized: "Name") : draft.trimmedAddress, text: $draft.name)
                    TextField("Comment", text: $draft.comment)
                } header: {
                    RXSectionHeader("Name")
                }

                Section {
                    Picker("Connect through", selection: $draft.transport) {
                        Text("Direct (TCP)").tag(RDMachine.Transport.direct)
                        Text("ProxyJump (Bastion)").tag(RDMachine.Transport.proxyJump)
                        Text("Cloudflare Access").tag(RDMachine.Transport.cloudflareAccess)
                        Text("NetEase UU Remote").tag(RDMachine.Transport.uuRemote)
                    }
                    if draft.transport == .proxyJump {
                        let choices = jumpServerChoices
                        LabeledContent("Jump server") {
                            // A menu, so the servers that cannot be chosen show
                            // disabled with the reason.
                            Menu {
                                ForEach(choices) { choice in
                                    Toggle(choice.title, isOn: Binding(
                                        get: { draft.proxyJumpMachineID == choice.id },
                                        set: { _ in draft.proxyJumpMachineID = choice.id }
                                    ))
                                    .disabled(choice.unavailableReason != nil)
                                }
                            } label: {
                                Text(choices.first { $0.id == draft.proxyJumpMachineID }?.machine.name
                                    ?? (choices.isEmpty ? String(localized: "No other SSH servers saved") : String(localized: "Choose…")))
                            }
                        }
                    }
                    TextField(draft.transport == .cloudflareAccess ? "Access Hostname" : draft.transport == .uuRemote ? "Device ID" : "Host Address", text: $draft.address)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: draft.address) { newValue in
                            let get = newValue.replacingOccurrences(of: "。", with: ".")
                            if draft.address != get { draft.address = get }
                        }
                    TextField("Host Port", text: $draft.port)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numberPad)
                } header: {
                    RXSectionHeader("Address")
                } footer: {
                    if !draft.portIsValid {
                        Text(ServerDraft.Problem.invalidPort.localizedDescription)
                            .foregroundStyle(.rxDanger)
                    } else if draft.transport == .proxyJump {
                        Text("Reaches this server through an SSH tunnel opened on the jump server (ssh -J).")
                    }
                }

                if draft.transport == .cloudflareAccess {
                    Section {
                        TextField("Client ID (optional)", text: $draft.serviceTokenID)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        SecureField("Client Secret (optional)", text: $draft.serviceTokenSecret)
                    } header: {
                        RXSectionHeader("Cloudflare Access Service Token")
                    } footer: {
                        Text("Connects like ssh -o ProxyCommand='cloudflared access ssh --hostname %h'. Leave the service token empty when the application has no Access policy. The port only names the server's host key.")
                    }
                }

                if draft.transport == .uuRemote {
                    Section {
                    } header: {
                        RXSectionHeader("UU Remote Transport")
                    } footer: {
                        Text("SSH, SFTP and Monitor on this server tunnel through the UU Remote session's port mapping — open the Desktop first so the tunnel is live.")
                    }
                }

                Section {
                    Picker("Remote Desktop", selection: $draft.remoteDesktopProtocol) {
                        Text("None").tag(RDMachine.RemoteDesktopProtocolType.none)
                        Text("VNC").tag(RDMachine.RemoteDesktopProtocolType.vnc)
                        Text("UU Remote").tag(RDMachine.RemoteDesktopProtocolType.uuRemote)
                    }
                } header: {
                    RXSectionHeader("Remote Desktop")
                }

                if draft.remoteDesktopProtocol == .vnc {
                    Section {
                        TextField("VNC Port", text: $draft.vncPort)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.numberPad)
                        SecureField("VNC Password (empty = identity password)", text: $draft.vncPassword)
                        TextField("Mac User Name (empty = identity user)", text: $draft.vncUsername)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        Toggle("Tunnel over SSH", isOn: $draft.vncOverSSH)
                        Toggle("Shared session", isOn: $draft.vncShared)
                    } header: {
                        RXSectionHeader("VNC")
                    } footer: {
                        if !draft.vncPortIsValid {
                            Text(ServerDraft.Problem.invalidVNCPort.localizedDescription)
                                .foregroundStyle(.rxDanger)
                        }
                    }
                }

                if draft.remoteDesktopProtocol == .uuRemote {
                    Section {
                        if !uuAccount.desktopDevices.isEmpty {
                            Picker("UU Remote device", selection: $draft.uuDeviceID) {
                                Text("Manual / assist").tag("")
                                ForEach(uuAccount.desktopDevices, id: \.deviceID) { device in
                                    Text("\(device.alias.isEmpty ? device.deviceID : device.alias) · \(UUDeviceInfo.platformName(device.platform))")
                                        .tag(device.deviceID)
                                }
                            }
                        }
                        TextField("Device ID", text: $draft.uuDeviceID)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        TextField("Assist connect ID (optional)", text: $draft.uuAssistID)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        SecureField("Assist code (optional)", text: $draft.uuAssistCode)
                        Button {
                            openUUAccount = true
                        } label: {
                            Label("UU Remote Account & Devices…", systemImage: "person.crop.circle")
                        }
                    } header: {
                        RXSectionHeader("NetEase UU Remote")
                    }
                }

                Section {
                    Picker("Identity", selection: $draft.identity) {
                        Text("Automatic").tag(RDIdentity.ID?.none)
                        ForEach(identities) { item in
                            Text(item.group.isEmpty ? item.username : "\(item.username) · \(item.group)")
                                .tag(RDIdentity.ID?.some(item.id))
                        }
                    }
                    TextField(sshUsernamePlaceholder, text: $draft.sshUsername)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                } header: {
                    RXSectionHeader("Identity")
                } footer: {
                    if let aid = draft.identity {
                        Text("\((RayonStore.shared.identity(aid) ?? RDIdentity()).shortDescription())\nA user name here overrides the identity's for this server.")
                    } else {
                        Text("Tries each identity that authenticates automatically. A user name here overrides the identity's for this server.")
                    }
                }

                Section {
                    HStack {
                        TextField("Default", text: $draft.folder)
                            .textInputAutocapitalization(.never)
                        if !existingFolders.isEmpty {
                            Menu {
                                Button("Default") { draft.folder = "" }
                                Divider()
                                ForEach(existingFolders, id: \.self) { item in
                                    Button(item) { draft.folder = item }
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                            .accessibilityLabel("Existing Folders")
                        }
                    }
                } header: {
                    RXSectionHeader("Folder")
                }

                Section {
                    HStack {
                        Text("Start folder")
                        TextField("/", text: $draft.startFolder)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                            .font(.rxCode)
                    }
                } header: {
                    RXSectionHeader("SFTP")
                }

                if !isNew {
                    Section {
                        Text(banner.isEmpty ? "None" : "\(banner)")
                            .font(.rxCode)
                            .foregroundStyle(banner.isEmpty ? Color.rxInkSecondary : Color.rxInk)
                            .textSelection(.enabled)
                    } header: {
                        RXSectionHeader("Last banner")
                    }
                }

                if isNew {
                    Section {
                        Button {
                            createAndConnect()
                        } label: {
                            HStack {
                                Label("Add and Connect", systemImage: "bolt.horizontal")
                                Spacer()
                                if connecting { ProgressView() }
                            }
                        }
                        .disabled(!canSave || connecting)
                    } footer: {
                        if let connectError {
                            Text(connectError).foregroundStyle(.rxDanger)
                        } else {
                            Text("Checks the connection and finds an identity that signs in, then saves the server and opens a terminal.")
                        }
                    }
                }

                if let identity = inEditWith {
                    Section {
                        Button {
                            Indicator.confirm(
                                message: "Delete this server?",
                                destructive: true
                            ) { confirmed in
                                if confirmed {
                                    RayonStore.shared.deleteMachines([identity])
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Delete Server", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .rxGroupedList()
            .sheet(isPresented: $picksIdentity) {
                NavigationStack {
                    PickIdentityView { picked in
                        guard let picked else { return }
                        draft.identity = picked
                        createAndConnect()
                    }
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $openUUAccount) {
                NavigationStack {
                    UURemoteAccountView(onConnectDesktop: { machineID in
                        openUUAccount = false
                        ServerActions.openDesktop(machineID)
                    })
                    .navigationTitle("UU Remote")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { openUUAccount = false }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Server" : "Edit Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        completeSheet()
                    } label: {
                        Text(isNew ? "Add" : "Save").bold()
                    }
                    .disabled(connecting)
                }
            }
        }

        /// The identity's user name, which applies while the field is empty.
        var sshUsernamePlaceholder: String {
            guard let identity = draft.identity else { return String(localized: "User Name (empty = identity user)") }
            let username = (RayonStore.shared.identity(identity) ?? RDIdentity()).username
            return username.isEmpty ? String(localized: "User Name (empty = identity user)") : String(localized: "User Name (empty = \(username))")
        }

        /// The server as the form describes it, on top of what is saved, so
        /// fields this form does not show are kept.
        func makeMachine() -> RDMachine {
            let saved = inEditWith.flatMap { RayonStore.shared.machine($0) }
                // A new server has never been connected to; RXFormat shows the epoch as "Never".
                ?? RDMachine(lastConnection: Date(timeIntervalSince1970: 0))
            return draft.apply(to: saved, folderId: RayonStore.shared.folderId(forName: draft.folder))
        }

        func validate() -> Bool {
            if let problem = draft.problem {
                Indicator.error(problem.localizedDescription)
                return false
            }
            return true
        }

        /// Saves the server; false, with the reason shown, when it is refused.
        func save(_ machine: RDMachine) -> Bool {
            guard RayonStore.shared.save(machine) else {
                Indicator.alert(RayonStore.shared.problem(saving: machine).map { "\($0.localizedDescription)" } ?? "The server could not be saved.")
                return false
            }
            return true
        }

        func completeSheet() {
            guard validate(), save(makeMachine()) else { return }
            dismiss()
        }

        /// Connects first; when no identity authenticates, asks for one.
        func createAndConnect() {
            guard validate() else { return }
            connectError = nil
            connecting = true
            let machine = makeMachine()
            let host = draft.trimmedAddress
            let port = draft.port
            let chosen = draft.identity.flatMap { RayonStore.shared.identity($0) }
            let candidates = RayonStore.shared.identitiesForAutoAuth
            let timeout = NSNumber(value: AppSettings.connectionTimeout.value)
            Task {
                let outcome = await ServerConnectionCheck.run(machine, identity: chosen, candidates: candidates, timeout: timeout)
                connecting = false
                switch outcome {
                case let .unreachable(refusal):
                    connectError = refusal ?? String(localized: "Could not reach \(host) on port \(port).")
                case let .authenticated(identity, banner):
                    var created = machine
                    created.associatedIdentity = identity
                    created.lastBanner = banner
                    created.lastConnection = Date()
                    guard save(created) else { return }
                    dismiss()
                    TerminalManager.shared.begin(for: created.id)
                case .rejected:
                    if chosen != nil {
                        connectError = String(localized: "The selected identity could not sign in to \(host).")
                    } else {
                        connectError = String(localized: "No identity that authenticates automatically could sign in. Choose an identity.")
                        picksIdentity = true
                    }
                }
            }
        }
    }

    struct EditMachineView_Previews: PreviewProvider {
        static var previews: some View {
            createPreview { AnyView(EditMachineView()) }
        }
    }

#endif
