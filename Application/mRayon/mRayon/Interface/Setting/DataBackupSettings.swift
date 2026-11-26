//
//  DataBackupSettings.swift
//  mRayon
//
//  Backup export and import, and the OpenSSH config importer, under
//  Settings › General › Data; the importer also sits in the Servers menu.
//  Files come and go through the Files app's pickers.
//

import RayonModule
import SwiftUI
import UniformTypeIdentifiers

/// A backup file to save: written to a temporary file first, then handed
/// to the Files app.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    /// Writes with `write` to a temporary file and keeps what it wrote.
    init(writing write: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try write(url)
        data = try Data(contentsOf: url)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Where an OpenSSH config comes from: the whole .ssh folder, so the keys it
/// names load too, or the config file alone.
enum SSHConfigSource: Identifiable {
    case folder
    case file

    var id: Self { self }

    var contentTypes: [UTType] {
        switch self {
        case .folder: return [.folder]
        case .file: return [.item]
        }
    }
}

enum DataImport {
    /// Imports the config at `url` (a .ssh folder or a config file) and
    /// says what came in.
    @MainActor
    static func importSSHConfig(from url: URL, source: SSHConfigSource) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let configURL = source == .folder ? url.appendingPathComponent("config") : url
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            UIBridge.presentError(with: source == .folder
                ? "There is no readable config file in \(url.lastPathComponent)."
                : "Could not read \(url.lastPathComponent) as UTF-8 text.")
            return
        }
        let keys = source == .folder ? url : nil
        let result = RayonStore.shared.importOpenSSHConfig(
            text,
            baseDirectory: configURL.deletingLastPathComponent(),
            keyDirectory: keys
        )
        UIBridge.presentSuccess(
            with: "Imported \(result.importedServers) servers and \(result.importedIdentities) identities",
            subtitle: source == .file && result.importedIdentities > 0
                ? "Keys load only when you import the whole .ssh folder."
                : nil
        )
    }

    /// A copy of a picked file the app may read for as long as it needs.
    static func readableCopy(of url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    /// Restores the backup at `url`; false when its password was wrong.
    @MainActor
    static func restoreBackup(_ url: URL, password: String?) -> Bool {
        do {
            let contents = try DataBackup.read(url, password: password)
            let result = RayonStore.shared.restore(contents)
            try? FileManager.default.removeItem(at: url)
            UIBridge.presentSuccess(
                with: "Backup imported",
                subtitle: "\(result.machines) servers, \(result.identities) identities, \(result.snippets) snippets, and \(result.forwards) port forwards."
            )
            return true
        } catch BackupError.wrongPassword {
            return false
        } catch {
            try? FileManager.default.removeItem(at: url)
            UIBridge.presentError(with: "Could not import backup: \(error.localizedDescription)")
            return true
        }
    }

    @MainActor
    static func restorePreferences(from url: URL) {
        do {
            let copy = try readableCopy(of: url)
            defer { try? FileManager.default.removeItem(at: copy) }
            try PreferencesBackup.restore(from: copy)
            RayonStore.shared.reloadPreferences()
            UIBridge.presentSuccess(with: "Settings imported")
        } catch {
            UIBridge.presentError(with: "Could not import settings: \(error.localizedDescription)")
        }
    }
}

extension View {
    /// Presents the Files picker for an OpenSSH config while `source` is set.
    func sshConfigImporter(_ source: Binding<SSHConfigSource?>) -> some View {
        modifier(SSHConfigImporter(source: source))
    }
}

private struct SSHConfigImporter: ViewModifier {
    @Binding var source: SSHConfigSource?

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: Binding(get: { source != nil }, set: { if !$0 { source = nil } }),
            allowedContentTypes: source?.contentTypes ?? [.item]
        ) { result in
            let picked = source ?? .file
            source = nil
            switch result {
            case let .success(url):
                DataImport.importSSHConfig(from: url, source: picked)
            case let .failure(error):
                UIBridge.presentError(with: error.localizedDescription)
            }
        }
    }
}

/// The ssh_config import entries for a menu.
struct SSHConfigImportMenuItems: View {
    @Binding var source: SSHConfigSource?

    var body: some View {
        Button {
            source = .folder
        } label: {
            Label("Import .ssh Folder…", systemImage: "folder.badge.gearshape")
        }
        Button {
            source = .file
        } label: {
            Label("Import ssh_config File…", systemImage: "square.and.arrow.down")
        }
    }
}

/// Settings rows: export and import a backup and the settings; import an
/// OpenSSH config.
struct DataBackupRows: View {
    var body: some View {
        RXDividedStack {
            BackupRow()
            PreferencesRow()
            SSHConfigRow()
        }
    }
}

private struct BackupRow: View {
    @State private var exportDocument: BackupDocument?
    @State private var choosingExport = false
    @State private var importing = false
    /// A picked backup waiting for its password.
    @State private var locked: URL?
    @State private var password = ""
    @State private var wrongPassword = false

    var body: some View {
        RXFormRow(
            "Backup",
            description: "Servers, identities, snippets, port forwards, folders and known host keys in one file. With passwords and keys, the file is protected by a password."
        ) {
            Menu {
                Button {
                    choosingExport = true
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                Button {
                    importing = true
                } label: {
                    Label("Import Backup…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Text("Backup")
            }
            .buttonStyle(.rx(size: .small))
            .fixedSize()
        }
        .sheet(isPresented: $choosingExport) {
            BackupExportForm { includeSecrets, password in
                choosingExport = false
                guard let includeSecrets else { return }
                do {
                    exportDocument = try BackupDocument {
                        try RayonStore.shared.exportBackup(to: $0, includeSecrets: includeSecrets, password: password)
                    }
                } catch {
                    UIBridge.presentError(with: "Could not export backup: \(error.localizedDescription)")
                }
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .data,
            defaultFilename: "Rayon.\(DataBackup.fileExtension)"
        ) { result in
            exportDocument = nil
            switch result {
            case let .success(url):
                UIBridge.presentSuccess(with: "Exported backup to \(url.lastPathComponent)")
            case let .failure(error):
                UIBridge.presentError(with: "Could not export backup: \(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            switch result {
            case let .success(url):
                do {
                    let copy = try DataImport.readableCopy(of: url)
                    if DataBackup.needsPassword(copy) {
                        password = ""
                        wrongPassword = false
                        locked = copy
                    } else {
                        _ = DataImport.restoreBackup(copy, password: nil)
                    }
                } catch {
                    UIBridge.presentError(with: "Could not read backup: \(error.localizedDescription)")
                }
            case let .failure(error):
                UIBridge.presentError(with: error.localizedDescription)
            }
        }
        .alert(
            "Backup Password",
            isPresented: Binding(get: { locked != nil }, set: { if !$0 { locked = nil } })
        ) {
            SecureField("Password", text: $password)
            Button("Cancel", role: .cancel) {
                if let locked { try? FileManager.default.removeItem(at: locked) }
                locked = nil
            }
            Button("Import") {
                guard let url = locked else { return }
                locked = nil
                if !DataImport.restoreBackup(url, password: password) {
                    password = ""
                    wrongPassword = true
                    // Asked again once this alert has gone.
                    DispatchQueue.main.async { locked = url }
                }
            }
        } message: {
            Text(wrongPassword ? "That password does not open this backup." : "This backup is protected by a password.")
        }
    }
}

/// What goes in a backup, and the password that protects it.
private struct BackupExportForm: View {
    /// Nil when cancelled; else whether passwords and keys go in, and the
    /// password.
    let onComplete: (Bool?, String?) -> Void

    @State private var includeSecrets = true
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include passwords and keys", isOn: $includeSecrets)
                } footer: {
                    Text("Passwords and keys go in only with a password; without it, the file cannot be opened.")
                }
                if includeSecrets {
                    Section {
                        SecureField("Password", text: $password)
                        SecureField("Confirm password", text: $confirmation)
                    } footer: {
                        if !confirmation.isEmpty, password != confirmation {
                            Text("The passwords differ.")
                        }
                    }
                }
            }
            .navigationTitle("Export Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete(nil, nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { onComplete(includeSecrets, includeSecrets ? password : nil) }
                        .disabled(includeSecrets && (password.isEmpty || password != confirmation))
                }
            }
        }
    }
}

private struct PreferencesRow: View {
    @State private var exportDocument: BackupDocument?
    @State private var importing = false

    var body: some View {
        RXFormRow(
            "Settings",
            description: "Rayon's settings, apart from the data, to bring to another device."
        ) {
            Menu {
                Button {
                    do {
                        exportDocument = try BackupDocument { try PreferencesBackup.export(to: $0) }
                    } catch {
                        UIBridge.presentError(with: "Could not export settings: \(error.localizedDescription)")
                    }
                } label: {
                    Label("Export Settings…", systemImage: "square.and.arrow.up")
                }
                Button {
                    importing = true
                } label: {
                    Label("Import Settings…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Text("Settings")
            }
            .buttonStyle(.rx(size: .small))
            .fixedSize()
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .data,
            defaultFilename: "Rayon.\(PreferencesBackup.fileExtension)"
        ) { result in
            exportDocument = nil
            if case let .failure(error) = result {
                UIBridge.presentError(with: "Could not export settings: \(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            switch result {
            case let .success(url): DataImport.restorePreferences(from: url)
            case let .failure(error): UIBridge.presentError(with: error.localizedDescription)
            }
        }
    }
}

private struct SSHConfigRow: View {
    @State private var source: SSHConfigSource?

    var body: some View {
        RXFormRow(
            "OpenSSH config",
            description: "Import Host entries, IdentityFile keys, and ProxyJump links from an OpenSSH config. Pick the whole .ssh folder so the keys it names load too."
        ) {
            Menu {
                SSHConfigImportMenuItems(source: $source)
            } label: {
                Text("Import")
            }
            .buttonStyle(.rx(size: .small))
            .fixedSize()
        }
        .sshConfigImporter($source)
    }
}
