//
//  FolderActions+macOS.swift
//  Rayon
//
//  Folders of servers: making, renaming and deleting them, moving servers
//  between them, and the header each one has in the Servers table. A folder
//  linked to a UU Remote account shows the account and refreshes from it.
//

#if os(macOS)
    import RayonDesign
    import RayonModule
    import SwiftUI

    @MainActor
    enum FolderActions {
        @MainActor
        static func newFolder(moving servers: [RDMachine.ID] = []) {
            let store = RayonStore.shared
            AppRouter.shared.present { dismiss in
                FolderNameSheet(
                    title: "New Folder",
                    lead: "Name the folder.",
                    confirmTitle: "Create",
                    initialText: store.availableFolderName(String(localized: "New Folder"))
                ) { name in
                    dismiss()
                    guard let name else { return }
                    let folder = store.createFolder(named: name)
                    store.moveServers(servers, toFolder: folder.id)
                }
            }
        }

        @MainActor
        static func rename(_ name: String) {
            AppRouter.shared.present { dismiss in
                FolderNameSheet(
                    title: "Rename Folder",
                    lead: "The servers in it move with it.",
                    confirmTitle: "Rename",
                    initialText: name
                ) { newName in
                    dismiss()
                    guard let newName else { return }
                    if let folder = RayonStore.shared.folder(named: name), !RayonStore.shared.renameFolder(folder.id, to: newName) {
                        Indicator.error(String(localized: "There is already a folder named \"\(newName)\"."))
                    }
                }
            }
        }

        @MainActor
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
                MainActor.assumeIsolated {
                    plan.perform()
                }
            }
        }

        /// Signs in to UU Remote; once signed in, the account's devices fill a
        /// folder of their own.
        @MainActor
        static func linkUURemote() {
            AppRouter.shared.present { dismiss in
                UURemoteAccountSheet(onConnectDesktop: { machineID in
                    dismiss()
                    AppRouter.shared.openDesktop(machine: machineID)
                }, onOpenTerminal: { machineID in
                    dismiss()
                    ServerTool.terminal.show(machineID)
                }, close: dismiss)
            }
        }
    }

    /// "Move to Folder" for a server's context menu.
    struct MoveToFolderMenu: View {
        let machine: RDMachine.ID
        // Not from the environment: a context menu may be built outside it.
        @ObservedObject private var store = RayonStore.shared

        var body: some View {
            let current = store.machine(machine)?.folderId
            // A linked folder is filled from its account, not by hand.
            let targets = store.folders.filter { !$0.isLinked }
            Menu {
                Button("Default") { store.moveServers([machine], toFolder: nil) }
                    .disabled(current == nil)
                if !targets.isEmpty { Divider() }
                ForEach(targets) { folder in
                    Button(folder.name) { store.moveServers([machine], toFolder: folder.id) }
                        .disabled(folder.id == current)
                }
                Divider()
                Button("New Folder…") { FolderActions.newFolder(moving: [machine]) }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
    }

    /// A folder's row in the Servers table: name and count; for a linked folder,
    /// the account and Refresh; its actions in a menu.
    struct FolderHeaderRow: View {
        let name: String
        let count: Int
        @EnvironmentObject var store: RayonStore
        @ObservedObject private var account = UURemoteAccount.shared
        @State private var refreshing = false
        @State private var refreshError: String?

        private var folder: RDFolder? { store.folder(named: name) }

        var body: some View {
            HStack(spacing: RX.Space.s2) {
                Image(systemName: folder?.isLinked == true ? "link" : "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.rxInkSecondary)
                    .accessibilityHidden(true)
                Text(name.isEmpty ? "Default" : "\(name)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.rxInkSecondary)
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.rxInkSecondary)
                if case .uuRemote = folder?.source {
                    linkedStatus
                }
                Spacer()
                if !name.isEmpty { menu }
            }
            .padding(.horizontal, RX.Space.s3)
            .padding(.top, RX.Space.s3)
            .padding(.bottom, 6)
            .contextMenu { if !name.isEmpty { menuItems } }
        }

        @ViewBuilder private var linkedStatus: some View {
            let signedIn = account.isLoggedIn && folder == account.folder(store: store)
            Text("·").foregroundStyle(.rxInkSecondary)
            Text(signedIn ? (account.nickname.isEmpty ? "Signed in" : "\(account.nickname)") : "Signed out")
                .font(.system(size: 11))
                .foregroundStyle(signedIn ? Color.rxInkSecondary : Color.rxWarning)
                .lineLimit(1)
            if signedIn {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.rx(.plain, size: .small))
                .disabled(refreshing)
                .help(refreshError.map { "\($0)" } ?? "Fetch the account's devices again")
            } else {
                Button("Sign In…") { FolderActions.linkUURemote() }
                    .buttonStyle(.rx(.plain, size: .small))
            }
            if let refreshError {
                Text(refreshError)
                    .font(.system(size: 11))
                    .foregroundStyle(.rxDanger)
                    .lineLimit(1)
            }
        }

        private var menu: some View {
            Menu {
                menuItems
            } label: {
                Label("Folder Actions", systemImage: "ellipsis")
            }
            .moreMenu()
        }

        @ViewBuilder private var menuItems: some View {
            if case .uuRemote = folder?.source {
                Button("UU Remote Account…") { FolderActions.linkUURemote() }
                Divider()
            }
            Button("Rename…") { FolderActions.rename(name) }
            // A linked folder goes with its account: deleting it signs out.
            if folder?.isLinked == true {
                Button("Remove Folder and Sign Out…", role: .destructive) { FolderActions.delete(name) }
            } else {
                Button("Delete Folder…", role: .destructive) { FolderActions.delete(name) }
            }
        }

        private func refresh() {
            refreshing = true
            refreshError = nil
            Task { @MainActor in
                defer { refreshing = false }
                do {
                    try await account.refreshDevices()
                } catch {
                    refreshError = error.localizedDescription
                }
            }
        }
    }

    private struct FolderNameSheet: View {
        let title: LocalizedStringResource
        let lead: LocalizedStringResource
        let confirmTitle: LocalizedStringResource
        let initialText: String
        let onComplete: (String?) -> Void

        @State private var text = ""

        private var trimmed: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var body: some View {
            SheetScaffold(title, lead: lead) {
                RXField("Folder name") {
                    TextField("Folder name", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !trimmed.isEmpty { onComplete(trimmed) }
                        }
                }
            } footer: {
                Button("Cancel") { onComplete(nil) }
                    .buttonStyle(.rx)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle) { onComplete(trimmed) }
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
            .frame(width: 420)
            .onAppear { text = initialText }
        }
    }

#endif
