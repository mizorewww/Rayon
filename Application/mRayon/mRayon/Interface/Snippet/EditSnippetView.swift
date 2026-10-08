//
//  EditSnippetView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/3.
//

import CodeEditorUI
import RayonModule
import SwiftUI
import SymbolPicker

struct EditSnippetView: View {
    @Environment(\.dismiss) private var dismiss

    let inEditWith: (() -> (UUID?))?

    init(requestIdentity: (() -> (UUID?))? = nil) {
        inEditWith = requestIdentity
    }

    let editor = SCodeEditor()

    @State var initializedOnce = false

    @State var name: String = ""
    @State var group: String = ""
    @State var code: String = ""
    @State var comment: String = ""
    @State var avatar: String = ""

    @State var openSymbolPicker: Bool = false

    var body: some View {
        List {
            Section {
                TextField("Snippet Name (Required)", text: $name)
                Button {
                    openSymbolPicker = true
                } label: {
                    if avatar.isEmpty {
                        Text("Select SF Symbol")
                    } else {
                        Label("Select SF Symbol", systemImage: avatar.isEmpty ? "square.dashed" : avatar)
                    }
                }
                TextField("Group (Optional)", text: $group)
                TextField("Comment (Optional)", text: $comment)
            } header: {
                RXSectionHeader("Name")
            } footer: {
                Text(avatar.isEmpty ? "No Symbol Selected" : avatar)
                    .textSelection(.enabled)
            }

//                Group is not available on iOS, :P
//                Section {
//                    TextField("Group", text: $group)
//                } header: {
//                    Label("Group", systemImage: "square.stack.3d.down.right")
//                } footer: {
//                    Text("")
//                }

            Section {
                editor
                    .onContentChange { code = $0 }
                    .frame(height: 250)
            } header: {
                RXSectionHeader("Code")
            }

            if let identity = inEditWith?() {
                Section {
                    Button {
                        UIBridge.requiresConfirmation(
                            message: "Delete this snippet?"
                        ) { confirmed in
                            if confirmed {
                                RayonStore.shared.snippetGroup.delete(identity)
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Delete Snippet", systemImage: "trash")
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
                    let read = RayonStore.shared.snippetGroup[edit]
                    name = read.name
                    group = read.group
                    code = read.code
                    comment = read.comment
                    avatar = read.getSFAvatar()
                }
                if comment.isEmpty {
                    comment = "Created at: " + Date().formatted()
                }
                if code.isEmpty {
                    editor.setDocumentData("#!/bin/bash\n\n")
                } else {
                    editor.setDocumentData(code)
                }
            }
        }
        .sheet(isPresented: $openSymbolPicker, onDismiss: nil) {
            SymbolPicker(symbol: $avatar)
        }
        .rxGroupedList()
        .navigationTitle(inEditWith?() == nil ? "New Snippet" : "Edit Snippet")
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
        guard !name.isEmpty else {
            UIBridge.presentError(with: "Empty Name")
            return
        }

        var id = UUID()
        if let inEditWith = inEditWith,
           let readId = inEditWith()
        {
            id = readId
        }

        var newSnippet = RDSnippet(
            id: id,
            name: name,
            group: group,
            code: code,
            comment: comment,
            attachment: [:]
        )
        if avatar.isEmpty {
            newSnippet.clearSFAvatar()
        } else {
            newSnippet.setSFAvatar(sfSymbol: avatar)
        }

        RayonStore.shared.snippetGroup.insert(newSnippet)

        dismiss()
    }
}

struct EditSnippetView_Previews: PreviewProvider {
    static var previews: some View {
        createPreview { AnyView(EditSnippetView()) }
    }
}
