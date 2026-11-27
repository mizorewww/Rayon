//
//  FolderActions.swift
//  Rayon
//
//  Folders of servers: making, renaming and deleting them, moving servers
//  between them, and the header each one has on the Servers page. A folder
//  linked to a UU Remote account shows the account and refreshes from it.
//

import RayonModule
import SwiftUI

@MainActor
enum FolderActions {
    static func newFolder(moving servers: [RDMachine.ID] = []) {
        let store = RayonStore.shared
        Indicator.input(
            title: "New Folder",
            message: "Name the folder.",
            placeholder: "Folder name",
            text: store.availableFolderName(String(localized: "New Folder"))
        ) { text in
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let folder = store.createFolder(named: name)
            store.moveServers(servers, toFolder: folder.id)
        }
    }

    static func rename(_ name: String) {
        Indicator.input(
            title: "Rename Folder",
            message: "The servers in it move with it.",
            placeholder: "Folder name",
            text: name
        ) { text in
            let newName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else { return }
            if let folder = RayonStore.shared.folder(named: name), !RayonStore.shared.renameFolder(folder.id, to: newName) {
                Indicator.error(String(localized: "There is already a folder named \"\(newName)\"."))
            }
        }
    }

    static func delete(_ name: String) {
        guard let folder = RayonStore.shared.folder(named: name) else { return }
        let plan = FolderDeletionPlan(folder: folder)
        Indicator.confirm(
            message: "\(plan.message)",
            informative: plan.informative.map { "\($0)" },
            confirmTitle: "\(plan.confirmTitle)",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            plan.perform()
        }
    }

    /// Fetches the linked account's devices again; they fill its folder.
    static func refreshLinked() async {
        do {
            try await UURemoteAccount.shared.refreshDevices()
        } catch {
            Indicator.error(error.localizedDescription)
        }
    }

    /// Signs in to UU Remote; once signed in, the account's devices fill a
    /// folder of their own.
    static func linkUURemote() {
        #if os(macOS)
            AppRouter.shared.present { dismiss in
                UURemoteAccountSheet(onConnectDesktop: { machineID in
                    dismiss()
                    AppRouter.shared.openDesktop(machine: machineID)
                }, onOpenTerminal: { machineID in
                    dismiss()
                    ServerTool.terminal.show(machineID)
                }, close: dismiss)
            }
        #else
            RayonUtil.presentModalSheet(rootView: UURemoteAccountSheet())
        #endif
    }
}

/// "Move to Folder" for the servers' menu; a checkmark on the folder they
/// are all in.
struct MoveToFolderMenu: View {
    let machines: [RDMachine.ID]
    // Not from the environment: a context menu may be built outside it.
    @ObservedObject private var store = RayonStore.shared

    var body: some View {
        Menu {
            Toggle("Default", isOn: isIn(nil))
            // A linked folder is filled from its account, not by hand.
            Section {
                ForEach(store.folders.filter { !$0.isLinked }) { folder in
                    Toggle(folder.name, isOn: isIn(folder.id))
                }
            }
            Section {
                Button("New Folder…", systemImage: "folder.badge.plus") {
                    FolderActions.newFolder(moving: machines)
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
    }

    private func isIn(_ folder: RDFolder.ID?) -> Binding<Bool> {
        Binding(
            get: { machines.allSatisfy { store.machine($0)?.folderId == folder } },
            set: { _ in store.moveServers(machines, toFolder: folder) }
        )
    }
}

/// A folder's header on the Servers page: name and count; for a linked
/// folder, the account; its actions in a menu.
struct FolderHeader: View {
    let name: String
    let count: Int
    @ObservedObject private var store = RayonStore.shared
    @ObservedObject private var account = UURemoteAccount.shared

    var body: some View {
        let folder = store.folder(named: name)
        HStack(spacing: RX.Space.s2) {
            Label(name.isEmpty ? "Default" : "\(name)", systemImage: folder?.isLinked == true ? "link" : "folder")
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.rxInkSecondary)
            if case .uuRemote = folder?.source {
                let signedIn = account.isLoggedIn && folder == account.folder(store: store)
                Text(signedIn ? (account.nickname.isEmpty ? "Signed in" : "\(account.nickname)") : "Signed out")
                    .foregroundStyle(signedIn ? Color.rxInkSecondary : Color.rxWarning)
                    .lineLimit(1)
                    .textCase(nil)
            }
            if count == 0 {
                Text(folder?.isLinked == true ? "No desktop devices on the account" : "Empty — move servers here from their menu")
                    .foregroundStyle(.rxInkSecondary)
                    .lineLimit(1)
                    .textCase(nil)
            }
            Spacer()
            if !name.isEmpty {
                Menu {
                    FolderMenuItems(name: name)
                } label: {
                    Label("Folder Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                #if os(macOS)
                .moreMenu()
                #endif
            }
        }
        .contextMenu { if !name.isEmpty { FolderMenuItems(name: name) } }
    }
}

/// For a linked folder, its account and Refresh Devices; Rename and Delete.
struct FolderMenuItems: View {
    let name: String
    @ObservedObject private var store = RayonStore.shared
    @ObservedObject private var account = UURemoteAccount.shared

    var body: some View {
        let folder = store.folder(named: name)
        if case .uuRemote = folder?.source {
            Section {
                Button(account.isLoggedIn ? "UU Remote Account…" : "Sign In…", systemImage: "person.crop.circle") {
                    FolderActions.linkUURemote()
                }
                if account.isLoggedIn, folder == account.folder(store: store) {
                    Button("Refresh Devices", systemImage: "arrow.clockwise") {
                        Task { await FolderActions.refreshLinked() }
                    }
                }
            }
        }
        Button("Rename…", systemImage: "pencil") { FolderActions.rename(name) }
        // A linked folder goes with its account: deleting it signs out.
        Button(folder?.isLinked == true ? "Remove Folder and Sign Out…" : "Delete Folder…", systemImage: "trash", role: .destructive) {
            FolderActions.delete(name)
        }
    }
}
