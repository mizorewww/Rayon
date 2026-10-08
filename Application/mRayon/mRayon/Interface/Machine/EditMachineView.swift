//
//  EditMachineView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/3.
//

import RayonModule
import SwiftUI

struct EditMachineView: View {
    @Environment(\.dismiss) private var dismiss

    let inEditWith: (() -> (UUID?))?

    init(requestIdentity: (() -> (UUID?))? = nil) {
        inEditWith = requestIdentity
    }

    @State var initializedOnce = false

    @State var remoteAddress = ""
    @State var remotePort = ""
    @State var name = ""
    @State var group = ""
    @State var comment = ""
    @State var associatedIdentity: UUID? = nil

    // Extra
    @State var fileTransferLoginPath: String = "/"

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                TextField("Comment (Optional)", text: $comment)
            } header: {
                RXSectionHeader("Name")
            }

            Section {
                TextField("Host Address", text: $remoteAddress)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .onChange(of: remoteAddress) { newValue in
                        let get = newValue.replacingOccurrences(of: "。", with: ".")
                        if remoteAddress != get { remoteAddress = get }
                    }
                TextField("Host Port", text: $remotePort)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numberPad)
            } header: {
                RXSectionHeader("Address")
            }

            Section {
                Button {
                    DispatchQueue.global().async {
                        let identity = RayonUtil.selectIdentity()
                        mainActor {
                            self.associatedIdentity = identity
                        }
                    }
                } label: {
                    Label("Select Identity", systemImage: "arrow.right")
                        .foregroundColor(.accentColor)
                }
            } header: {
                RXSectionHeader("Identity")
            } footer: {
                if let aid = associatedIdentity {
                    Text(RayonStore.shared.identityGroup[aid].shortDescription())
                } else {
                    Text("No Associated Identity (Optional)")
                }
            }

            Section {
                TextField("Default", text: $group)
                    .textInputAutocapitalization(.never)
            } header: {
                RXSectionHeader("Group")
            } footer: {
                Text("Items with the same group are listed together.")
            }

            Section {
                HStack {
                    Text("Login Path: ")
                    TextField("", text: $fileTransferLoginPath)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
            } header: {
                RXSectionHeader("SFTP")
            } footer: {
                Text("Customization about SFTP features")
            }

            if let identity = inEditWith?() {
                Section {
                    Button {
                        UIBridge.requiresConfirmation(
                            message: "Delete this server?"
                        ) { confirmed in
                            if confirmed {
                                RayonStore.shared.machineGroup.delete(identity)
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
        .onAppear {
            if initializedOnce { return }
            initializedOnce = true
            mainActor(delay: 0.1) { // <-- SwiftUI bug here, don't remove
                if let edit = inEditWith?() {
                    let read = RayonStore.shared.machineGroup[edit]
                    remoteAddress = read.remoteAddress
                    remotePort = read.remotePort
                    name = read.name
                    group = read.group
                    comment = read.comment
                    fileTransferLoginPath = read.fileTransferLoginPath
                    if let aid = read.associatedIdentity {
                        associatedIdentity = UUID(uuidString: aid)
                    }
                }
                if comment.isEmpty {
                    comment = "Created at: " + Date().formatted()
                }
                if remotePort.isEmpty {
                    remotePort = "22"
                }
            }
        }
        .rxGroupedList()
        .navigationTitle(inEditWith?() == nil ? "New Server" : "Edit Server")
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

    func completeSheet() {
        guard !name.isEmpty else {
            UIBridge.presentError(with: "Empty Name")
            return
        }
        guard !remoteAddress.isEmpty else {
            UIBridge.presentError(with: "Empty Address")
            return
        }
        guard !remotePort.isEmpty else {
            UIBridge.presentError(with: "Empty Port")
            return
        }

        var id = UUID()
        if let inEditWith = inEditWith,
           let readId = inEditWith()
        {
            id = readId
        }

        var newMachine = RDMachine(
            id: id,
            remoteAddress: remoteAddress,
            remotePort: remotePort,
            name: name,
            group: group,
            comment: comment,
            associatedIdentity: associatedIdentity?.uuidString
        )
        newMachine.fileTransferLoginPath = fileTransferLoginPath
        RayonStore.shared.machineGroup.insert(newMachine)

        dismiss()
    }
}

struct EditMachineView_Previews: PreviewProvider {
    static var previews: some View {
        createPreview { AnyView(EditMachineView()) }
    }
}
