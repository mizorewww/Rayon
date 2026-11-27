//
//  FileActionsMenu.swift
//  Rayon
//
//  What can be done to the chosen files, as a context menu or a row's menu.
//

import RayonModule
import SwiftUI

struct FileActionsMenu: View {
    @ObservedObject var browser: FileBrowser
    let files: [FileBrowser.File]

    var body: some View {
        if files.count == 1, let file = files.first {
            Section {
                if file.isFolder {
                    Button { browser.open(file) } label: {
                        Label("Open", systemImage: "arrow.right")
                    }
                } else {
                    let tooLarge = !FileTransferContext.isEditable(file)
                    Button { browser.edit(file) } label: {
                        Label(tooLarge ? "Too Large to Edit" : "Edit", systemImage: "square.and.pencil")
                    }
                    .disabled(tooLarge)
                }
                download
            }
            Section {
                Button { browser.ask(.rename(file.name)) } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button { Pasteboard.copy(file.name) } label: {
                    Label("Copy Name", systemImage: "doc.on.doc")
                }
                Button { Pasteboard.copy(file.url.path) } label: {
                    Label("Copy Path", systemImage: "link")
                }
            }
        } else {
            download
        }
        Section {
            Button(role: .destructive) { browser.delete(files) } label: {
                Label("Delete…", systemImage: "trash")
            }
        }
    }

    private var download: some View {
        Button { browser.download(files) } label: {
            #if os(macOS)
                Label("Download…", systemImage: "arrow.down.doc")
            #else
                Label("Download", systemImage: "arrow.down.doc")
            #endif
        }
    }
}
