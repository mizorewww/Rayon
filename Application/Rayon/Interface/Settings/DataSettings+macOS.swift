//
//  DataSettings+macOS.swift
//  Rayon
//
//  Settings › General › Data on the Mac: backups of the data and of the
//  settings, and the OpenSSH `~/.ssh/config` importer.
//

#if os(macOS)
    import AppKit
    import RayonModule
    import SwiftUI
    import UniformTypeIdentifiers

    struct DataSettings: View {
        /// A picked backup waiting for its password.
        private struct LockedBackup: Identifiable {
            let url: URL
            let retry: Bool
            var id: URL {
                url
            }
        }

        @ObservedObject private var store = RayonStore.shared
        @State private var statusMessage: String?
        @State private var importingBackup = false
        @State private var locked: LockedBackup?

        var body: some View {
            Group {
                LabeledContent {
                    HStack {
                        Button("Export Backup…") {
                            SheetPresenter.present { dismiss in
                                BackupExportSheet { includeSecrets, password in
                                    dismiss()
                                    if let includeSecrets {
                                        exportBackup(includeSecrets: includeSecrets, password: password)
                                    }
                                }
                            }
                        }
                        Button("Import Backup…") {
                            importingBackup = true
                        }
                    }
                } label: {
                    Text("Backup")
                    Text("Servers, identities, snippets, port forwards, folders and known host keys in one file. With passwords and keys, the file is protected by a password.")
                }
                LabeledContent {
                    HStack {
                        Button("Export Settings…") { exportPreferences() }
                        Button("Import Settings…") { importPreferences() }
                    }
                } label: {
                    Text("Settings")
                    Text("Rayon's settings, apart from the data, to bring to another Mac.")
                }
                LabeledContent {
                    Button("Import ~/.ssh/config…") { importSSHConfig() }
                } label: {
                    Text("OpenSSH config")
                    Text("Import Host entries, IdentityFile keys, and ProxyJump links from ~/.ssh/config or another OpenSSH config file.")
                }
                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
            // SwiftUI presents both against this window once the open panel is
            // gone; an AppKit sheet begun from the panel's completion attached
            // to the closing panel and left the window blocked.
            .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.item]) { result in
                switch result {
                case let .success(url):
                    importBackup(url)
                case let .failure(error):
                    Indicator.error(error.localizedDescription)
                }
            }
            .sheet(item: $locked) { backup in
                BackupPasswordSheet(fileName: backup.url.lastPathComponent, retry: backup.retry) { password in
                    locked = nil
                    if let password {
                        restoreBackup(backup.url, password: password)
                    } else {
                        backup.url.stopAccessingSecurityScopedResource()
                    }
                }
            }
        }

        private func savePanel(_ title: String, name: String) -> URL? {
            let panel = NSSavePanel()
            panel.title = title
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }

        private func chooseFile(_ message: String, then action: @escaping (URL) -> Void) {
            OpenPanel.present(
                message: message,
                prompt: "Import",
                directory: nil,
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: false,
                canCreateDirectories: false,
                showsHiddenFiles: false
            ) { urls in
                if let url = urls.first {
                    action(url)
                }
            }
        }

        private func exportBackup(includeSecrets: Bool, password: String?) {
            guard let url = savePanel("Export Rayon Backup", name: "Rayon.\(DataBackup.fileExtension)") else { return }
            Task {
                do {
                    try await store.exportBackup(to: url, includeSecrets: includeSecrets, password: password)
                    statusMessage = "Exported backup to \(url.lastPathComponent)."
                } catch {
                    Indicator.error("Could not export backup: \(error.localizedDescription)")
                }
            }
        }

        /// Keeps access to the picked file until the import ends, since a
        /// wrong password asks again.
        private func importBackup(_ url: URL) {
            _ = url.startAccessingSecurityScopedResource()
            if DataBackup.needsPassword(url) {
                locked = LockedBackup(url: url, retry: false)
            } else {
                restoreBackup(url, password: nil)
            }
        }

        private func restoreBackup(_ url: URL, password: String?) {
            Task {
                do {
                    let contents = try await DataBackup.load(url, password: password)
                    url.stopAccessingSecurityScopedResource()
                    let result = store.restore(contents)
                    statusMessage = "Imported \(result.summary)"
                } catch BackupError.wrongPassword {
                    locked = LockedBackup(url: url, retry: true)
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    Indicator.error("Could not import backup: \(error.localizedDescription)")
                }
            }
        }

        private func exportPreferences() {
            guard let url = savePanel("Export Rayon Settings", name: "Rayon.\(PreferencesBackup.fileExtension)") else { return }
            do {
                try PreferencesBackup.export(to: url)
                statusMessage = "Exported settings to \(url.lastPathComponent)."
            } catch {
                Indicator.error("Could not export settings: \(error.localizedDescription)")
            }
        }

        private func importPreferences() {
            chooseFile("Choose exported Rayon settings") { url in
                do {
                    try PreferencesBackup.restore(from: url)
                    statusMessage = "Imported settings."
                } catch {
                    Indicator.error("Could not import settings: \(error.localizedDescription)")
                }
            }
        }

        private func importSSHConfig() {
            let sshDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
            OpenPanel.present(
                message: "Choose an OpenSSH config file (e.g. ~/.ssh/config)",
                prompt: "Import",
                directory: sshDir,
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: false,
                canCreateDirectories: false,
                showsHiddenFiles: true
            ) { urls in
                guard let url = urls.first else { return }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    Indicator.error("Could not read \(url.lastPathComponent) as UTF-8 text.")
                    return
                }
                let result = store.importOpenSSHConfig(text, baseDirectory: url.deletingLastPathComponent())
                statusMessage = "Imported \(result.importedServers) servers and \(result.importedIdentities) identities from \(url.lastPathComponent)."
            }
        }
    }

    /// What goes in a backup, and the password that protects it.
    private struct BackupExportSheet: View {
        /// Nil when cancelled; else whether passwords and keys go in, and the
        /// password.
        let onComplete: (Bool?, String?) -> Void

        @State private var includeSecrets = true
        @State private var password = ""
        @State private var confirmation = ""

        private var ready: Bool {
            !includeSecrets || (!password.isEmpty && password == confirmation)
        }

        var body: some View {
            SheetScaffold("Export Backup", lead: "Passwords and keys go in only with a password; without it, the file cannot be opened.") {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    Toggle("Include passwords and keys", isOn: $includeSecrets)
                    if includeSecrets {
                        RXField("Password") {
                            SecureField("Password", text: $password)
                                .textFieldStyle(.rx)
                        }
                        RXField("Confirm password") {
                            SecureField("Confirm password", text: $confirmation)
                                .textFieldStyle(.rx)
                        }
                        if !confirmation.isEmpty, password != confirmation {
                            HelpText("The passwords differ.", isError: true)
                        }
                    }
                }
            } footer: {
                Button("Cancel") { onComplete(nil, nil) }
                    .buttonStyle(.rx)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export…") { onComplete(includeSecrets, includeSecrets ? password : nil) }
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
            .frame(width: 440)
        }
    }

    /// The password of a backup being imported.
    private struct BackupPasswordSheet: View {
        let fileName: String
        let retry: Bool
        let onComplete: (String?) -> Void

        @State private var password = ""

        var body: some View {
            SheetScaffold("Backup Password", lead: "\(fileName) is protected by a password.") {
                VStack(alignment: .leading, spacing: RX.Space.s2) {
                    RXField("Password") {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.rx)
                            .onSubmit {
                                if !password.isEmpty {
                                    onComplete(password)
                                }
                            }
                    }
                    if retry {
                        HelpText("That password does not open this backup.", isError: true)
                    }
                }
            } footer: {
                Button("Cancel") { onComplete(nil) }
                    .buttonStyle(.rx)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") { onComplete(password) }
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            .frame(width: 420)
        }
    }
#endif
