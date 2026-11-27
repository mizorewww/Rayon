//
//  ServerEditor.swift
//  Rayon
//
//  New / Edit Server: Name and Comment; Connect through (direct, a ProxyJump
//  bastion, Cloudflare Access or UU Remote) with its address and port;
//  Remote Desktop (VNC or UU Remote); Identity and user name; Folder and
//  SFTP start folder; Last banner (read-only). A new server can be checked
//  and connected before it is saved.
//

import RayonModule
import SwiftUI

struct ServerEditor: View {
    /// nil creates a new server.
    let machine: RDMachine.ID?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RayonStore.shared
    @ObservedObject private var uuAccount = UURemoteAccount.shared

    @State private var draft: ServerDraft
    /// What the server said last; shown, not edited.
    private let banner: String
    @State private var connecting = false
    @State private var connectError: String?
    @State private var picksIdentity = false
    @State private var showsUURemoteAccount = false

    /// - Parameter template: what a new server starts from (a host found
    ///   nearby); nothing is saved until Add.
    init(machine: RDMachine.ID? = nil, template: RDMachine? = nil) {
        self.machine = machine
        let read = machine.flatMap { RayonStore.shared.machine($0) } ?? template
        _draft = State(initialValue: read.map { ServerDraft($0, folder: RayonStore.shared.folderName(of: $0)) } ?? ServerDraft())
        banner = read?.lastBanner ?? ""
    }

    private var isNew: Bool { machine == nil }

    var body: some View {
        Form {
            Section("Name") {
                FormField("Name", text: $draft.name, prompt: draft.trimmedAddress.isEmpty ? Text("prod-web-01") : Text(verbatim: draft.trimmedAddress))
                FormField("Comment", text: $draft.comment, prompt: Text("Optional"))
            }
            addressSection
            if draft.transport == .cloudflareAccess {
                Section {
                    FormField("Service token Client ID", text: $draft.serviceTokenID, prompt: Text("Optional"), code: true)
                    FormField("Client Secret", text: $draft.serviceTokenSecret, prompt: Text("Optional"), secure: true, code: true)
                } header: {
                    Text("Cloudflare Access Service Token")
                } footer: {
                    Text("Connects like ssh -o ProxyCommand='cloudflared access ssh --hostname %h', without cloudflared. Leave the service token empty when the application has no Access policy. The port only names the server's host key.")
                }
            }
            remoteDesktopSection
            identitySection
            Section("Folder") {
                LabeledContent("Folder") {
                    HStack {
                        TextField("Folder", text: $draft.folder, prompt: Text("Default"))
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                        if !existingFolders.isEmpty {
                            Menu {
                                Button("Default") { draft.folder = "" }
                                Divider()
                                ForEach(existingFolders, id: \.self) { item in
                                    Button(item) { draft.folder = item }
                                }
                            } label: {
                                Label("Existing Folders", systemImage: "folder")
                                    .labelStyle(.iconOnly)
                            }
                            .fixedSize()
                        }
                    }
                }
                FormField("SFTP start folder", text: $draft.startFolder, prompt: Text("/"), code: true)
            }
            if !isNew {
                Section("Last banner") {
                    Text(banner.isEmpty ? "None" : "\(banner)")
                        .font(.rxCode)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(banner.isEmpty ? Color.rxInkSecondary : Color.rxInk)
                        .textSelection(.enabled)
                }
            }
            if isNew {
                Section {
                    Button(action: createAndConnect) {
                        HStack {
                            Label("Add and Connect", systemImage: "bolt.horizontal")
                            Spacer()
                            if connecting { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(!draft.isValid || connecting)
                    .help("Check the connection, then save the server")
                } footer: {
                    if let connectError {
                        Text(connectError).foregroundStyle(.rxDanger)
                    } else {
                        Text("Checks the connection and finds an identity that signs in, then saves the server and opens a terminal.")
                    }
                }
            } else if let machine {
                Section {
                    Button("Delete Server", systemImage: "trash", role: .destructive) {
                        ServerActions.delete([machine]) { dismiss() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save", action: saveAndClose)
                    .disabled(!draft.isValid || connecting)
            }
        }
        .editorSheet(isNew ? "New Server" : "Edit Server")
        .sheet(isPresented: $picksIdentity) {
            IdentityPicker { picked in
                guard let picked else { return }
                draft.identity = picked
                createAndConnect()
            }
        }
        .sheet(isPresented: $showsUURemoteAccount) {
            #if os(macOS)
                UURemoteAccountSheet(onConnectDesktop: { machineID in
                    showsUURemoteAccount = false
                    AppRouter.shared.openDesktop(machine: machineID)
                }, close: { showsUURemoteAccount = false })
            #else
                UURemoteAccountSheet()
            #endif
        }
    }

    // MARK: - Sections

    private var addressSection: some View {
        Section {
            Picker("Connect through", selection: $draft.transport) {
                Text("Direct (TCP)").tag(RDMachine.Transport.direct)
                Text("ProxyJump (Bastion)").tag(RDMachine.Transport.proxyJump)
                Text("Cloudflare Access").tag(RDMachine.Transport.cloudflareAccess)
                Text("NetEase UU Remote").tag(RDMachine.Transport.uuRemote)
            }
            if draft.transport == .proxyJump {
                let choices = store.jumpServerChoices(for: machine)
                    .sorted { $0.machine.name.localizedStandardCompare($1.machine.name) == .orderedAscending }
                LabeledContent("Jump server (Bastion)") {
                    // A menu rather than a Picker: a Picker's items cannot be
                    // disabled on macOS, and the unavailable ones are shown.
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
                            ?? (choices.isEmpty ? String(localized: "No other SSH servers saved") : String(localized: "Choose a jump server…")))
                    }
                    .fixedSize()
                }
            }
            switch draft.transport {
            case .cloudflareAccess:
                FormField("Access hostname", text: address, prompt: Text("ssh.example.com"), code: true)
            case .uuRemote:
                FormField("Device ID", text: address, prompt: Text("UU Remote device id"), code: true)
            default:
                FormField("Address", text: address, prompt: Text("Host name or IP address"), code: true)
            }
            FormField("Port", text: $draft.port, prompt: Text("22"), code: true)
                .numberPad()
        } header: {
            Text("Address")
        } footer: {
            if !draft.portIsValid {
                Text(ServerDraft.Problem.invalidPort.localizedDescription)
                    .foregroundStyle(.rxDanger)
            } else if draft.transport == .proxyJump {
                Text("Reaches this server through an SSH tunnel opened on the jump server (ssh -J).")
            } else if draft.transport == .uuRemote {
                Text("Files, Monitor and the editor reach the device's own SSH server through UU Remote, signed in with the identity below; on a Mac, turn on System Settings › General › Sharing › Remote Login. The terminal is UU Remote's own and needs neither.")
            }
        }
    }

    /// A full stop typed on a Chinese keyboard is a dot in an address.
    private var address: Binding<String> {
        Binding(get: { draft.address }, set: { draft.address = $0.replacingOccurrences(of: "。", with: ".") })
    }

    private var remoteDesktopSection: some View {
        Section {
            Picker("Remote Desktop", selection: $draft.remoteDesktopProtocol) {
                Text("None").tag(RDMachine.RemoteDesktopProtocolType.none)
                Text("VNC").tag(RDMachine.RemoteDesktopProtocolType.vnc)
                Text("NetEase UU Remote").tag(RDMachine.RemoteDesktopProtocolType.uuRemote)
            }
            if draft.remoteDesktopProtocol == .vnc {
                // Reached over an SSH local forward when the port only listens
                // on the remote loopback.
                FormField("VNC port", text: $draft.vncPort, prompt: Text("5900"), code: true)
                    .numberPad()
                FormField("VNC password", text: $draft.vncPassword, prompt: Text("Use identity password"), secure: true)
                FormField("Mac user name", text: $draft.vncUsername, prompt: Text("Use identity user name"), code: true)
                Toggle("Tunnel over SSH", isOn: $draft.vncOverSSH)
                Toggle("Shared session", isOn: $draft.vncShared)
            } else if draft.remoteDesktopProtocol == .uuRemote {
                uuFields
            }
        } header: {
            Text("Remote Desktop")
        } footer: {
            if draft.remoteDesktopProtocol == .vnc {
                if draft.vncPortIsValid {
                    Text("macOS Screen Sharing signs in with a Mac user name and password. Leave the VNC password empty to use the identity's; a VNC password alone uses VNC authentication.")
                } else {
                    Text(ServerDraft.Problem.invalidVNCPort.localizedDescription)
                        .foregroundStyle(.rxDanger)
                }
            } else if draft.remoteDesktopProtocol == .uuRemote, !uuAccount.isLoggedIn {
                Text("Sign in to a UU Remote account to pick a device, or paste a device id / assist code below.")
            }
        }
    }

    /// Which UU Remote device draws the screen: one off the signed-in
    /// account, a pasted id, or an assist code.
    @ViewBuilder private var uuFields: some View {
        let devices = uuAccount.desktopDevices
        if !devices.isEmpty {
            Picker("UU Remote device", selection: $draft.uuDeviceID) {
                Text("Manual / assist").tag("")
                // A device no longer on the account: a tagged row, or the Picker draws blank.
                if !draft.uuDeviceID.isEmpty, !devices.contains(where: { $0.deviceID == draft.uuDeviceID }) {
                    Text("\(draft.uuDeviceID) · not on this account").tag(draft.uuDeviceID)
                }
                ForEach(devices, id: \.deviceID) { device in
                    Text("\(device.alias.isEmpty ? device.deviceID : device.alias) · \(UUDeviceInfo.platformName(device.platform))")
                        .tag(device.deviceID)
                }
            }
        }
        // Typed in, or not on the account: the field stays while it is typed.
        if !devices.contains(where: { $0.deviceID == draft.uuDeviceID }) {
            FormField("Device ID", text: $draft.uuDeviceID, prompt: Text("From the account's device list"), code: true)
            FormField("Assist connect ID", text: $draft.uuAssistID, prompt: Text("Optional"), code: true)
            FormField("Assist code", text: $draft.uuAssistCode, prompt: Text("Optional"), secure: true, code: true)
        }
        LabeledContent {
            Button("UU Remote Account & Devices…") { showsUURemoteAccount = true }
        } label: {
            if uuAccount.isLoggedIn {
                Text(UURemoteAccount.deviceCount(devices.count))
            }
        }
    }

    private var identitySection: some View {
        Section {
            Picker("Identity", selection: $draft.identity) {
                Text("Automatic").tag(RDIdentity.ID?.none)
                // An identity deleted since: a tagged row, or the Picker draws blank.
                if let missing = draft.identity, store.identity(missing) == nil {
                    Text("Choose…").tag(RDIdentity.ID?.some(missing))
                }
                ForEach(identities) { item in
                    Text(item.group.isEmpty ? item.username : "\(item.username) · \(item.group)")
                        .tag(RDIdentity.ID?.some(item.id))
                }
            }
            FormField("User name", text: $draft.sshUsername, prompt: Text(sshUsernamePlaceholder), code: true)
        } header: {
            Text("Identity")
        } footer: {
            if let identity = draft.identity.flatMap({ store.identity($0) }) {
                Text("\(identity.shortDescription())\nA user name here overrides the identity's for this server.")
            } else {
                Text("Tries each identity that authenticates automatically. A user name here overrides the identity's for this server.")
            }
        }
    }

    private var identities: [RDIdentity] {
        store.identities.sorted { $0.username.localizedStandardCompare($1.username) == .orderedAscending }
    }

    private var existingFolders: [String] {
        Set(store.folders.map(\.name))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The identity's user name, which applies while the field is empty.
    private var sshUsernamePlaceholder: String {
        let username = draft.identity.flatMap { store.identity($0) }?.username ?? ""
        return username.isEmpty ? String(localized: "Use identity user name") : String(localized: "\(username) (from identity)")
    }

    // MARK: - Saving

    /// The server as the form describes it, on top of what is saved, so
    /// fields this form does not show are kept.
    private func makeMachine() -> RDMachine {
        let saved = machine.flatMap { store.machine($0) }
            // A new server has never been connected to; RXFormat shows the epoch as "Never".
            ?? RDMachine(lastConnection: Date(timeIntervalSince1970: 0))
        return draft.apply(to: saved, folderId: store.folderId(forName: draft.folder))
    }

    /// Saves the server; false, with the reason shown, when it is refused.
    private func save(_ target: RDMachine) -> Bool {
        guard store.save(target) else {
            Indicator.error(store.problem(saving: target)?.localizedDescription ?? String(localized: "The server could not be saved."))
            return false
        }
        return true
    }

    private func saveAndClose() {
        guard save(makeMachine()) else { return }
        dismiss()
    }

    /// Connects first; when no identity authenticates, asks for one.
    private func createAndConnect() {
        connectError = nil
        connecting = true
        let checked = makeMachine()
        let host = draft.trimmedAddress
        let port = draft.port
        let chosen = draft.identity.flatMap { store.identity($0) }
        let candidates = store.identitiesForAutoAuth
        let timeout = NSNumber(value: AppSettings.connectionTimeout.value)
        Task {
            let outcome = await ServerConnectionCheck.run(checked, identity: chosen, candidates: candidates, timeout: timeout)
            connecting = false
            switch outcome {
            case let .unreachable(refusal):
                connectError = refusal ?? String(localized: "Could not reach \(host) on port \(port).")
            case let .authenticated(identity, banner):
                var created = checked
                created.associatedIdentity = identity
                created.lastBanner = banner
                created.lastConnection = Date()
                guard save(created) else { return }
                dismiss()
                ServerTool.terminal.show(created.id)
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

private extension View {
    func numberPad() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
        #else
            self
        #endif
    }
}
