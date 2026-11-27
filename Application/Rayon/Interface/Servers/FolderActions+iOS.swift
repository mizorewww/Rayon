//
//  FolderActions+iOS.swift
//  Rayon
//
//  Folders of servers: making, renaming and deleting them, moving servers
//  between them, and the header each one has in the Servers list. A folder
//  linked to a UU Remote account shows the link and refreshes from it.
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    @MainActor
    enum FolderActions {
        @MainActor
        static func newFolder(moving servers: [RDMachine.ID] = []) {
            let store = RayonStore.shared
            Indicator.input(
                title: "New Folder",
                message: "Name the folder.",
                placeholder: "Folder name",
                text: store.availableFolderName("New Folder")
            ) { text in
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let folder = store.createFolder(named: name)
                store.moveServers(servers, toFolder: folder.id)
            }
        }

        @MainActor
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
                    Indicator.error("There is already a folder named \"\(newName)\".")
                }
            }
        }

        @MainActor
        static func delete(_ name: String) {
            guard let folder = RayonStore.shared.folder(named: name) else { return }
            let plan = FolderDeletionPlan(folder: folder)
            Indicator.confirm(
                message: plan.message,
                informative: plan.informative,
                confirmTitle: plan.confirmTitle,
                destructive: true
            ) { confirmed in
                guard confirmed else { return }
                plan.perform()
            }
        }

        /// Fetches the linked account's devices again; they fill its folder.
        @MainActor
        static func refreshLinked() {
            Task { @MainActor in
                do {
                    try await UURemoteAccount.shared.refreshDevices()
                } catch {
                    Indicator.error(error.localizedDescription)
                }
            }
        }
    }

    /// "Move to Folder" for a server's menu.
    struct MoveToFolderMenu: View {
        let machine: RDMachine.ID
        // Not from the environment: a menu may be built outside it.
        @ObservedObject private var store = RayonStore.shared

        var body: some View {
            let current = store.machine(machine)?.folderId
            // A linked folder is filled from its account, not by hand.
            let targets = store.folders.filter { !$0.isLinked }
            Menu {
                Button {
                    store.moveServers([machine], toFolder: nil)
                } label: {
                    Label("Default", systemImage: current == nil ? "checkmark" : "tray")
                }
                .disabled(current == nil)
                if !targets.isEmpty {
                    Section {
                        ForEach(targets) { folder in
                            Button {
                                store.moveServers([machine], toFolder: folder.id)
                            } label: {
                                Label(folder.name, systemImage: folder.id == current ? "checkmark" : "folder")
                            }
                            .disabled(folder.id == current)
                        }
                    }
                }
                Section {
                    Button {
                        FolderActions.newFolder(moving: [machine])
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
    }

    /// A folder's section header in the Servers list: name and count, and for
    /// a folder other than Default, its actions in a menu.
    struct FolderSectionHeader: View {
        let name: String
        let count: Int
        @EnvironmentObject var store: RayonStore
        @ObservedObject private var account = UURemoteAccount.shared

        private var folder: RDFolder? { store.folder(named: name) }

        var body: some View {
            HStack(spacing: RX.Space.s2) {
                if folder?.isLinked == true {
                    Image(systemName: "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.rxInkSecondary)
                        .accessibilityHidden(true)
                }
                RXSectionHeader(name.isEmpty ? "Default" : name)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.rxInkSecondary)
                if case .uuRemote = folder?.source {
                    Text(signedIn ? (account.nickname.isEmpty ? "Signed in" : account.nickname) : "Signed out")
                        .font(.caption)
                        .foregroundStyle(signedIn ? Color.rxInkSecondary : Color.rxWarning)
                        .lineLimit(1)
                        .textCase(nil)
                }
                Spacer()
                if !name.isEmpty {
                    Menu {
                        FolderMenuItems(name: name)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.rxInkSecondary)
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .accessibilityLabel("Folder Actions")
                }
            }
        }

        private var signedIn: Bool {
            account.isLoggedIn && folder == account.folder(store: store)
        }
    }

    /// Rename and Delete; for the signed-in account's folder, Refresh.
    struct FolderMenuItems: View {
        let name: String
        @ObservedObject private var store = RayonStore.shared
        @ObservedObject private var account = UURemoteAccount.shared

        var body: some View {
            let folder = store.folder(named: name)
            if case .uuRemote = folder?.source, account.isLoggedIn, folder == account.folder(store: store) {
                Button {
                    FolderActions.refreshLinked()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
            }
            Button {
                FolderActions.rename(name)
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            // A linked folder goes with its account: deleting it signs out.
            Button(role: .destructive) {
                FolderActions.delete(name)
            } label: {
                Label(folder?.isLinked == true ? "Remove Folder and Sign Out…" : "Delete Folder…", systemImage: "trash")
            }
        }
    }

#endif
