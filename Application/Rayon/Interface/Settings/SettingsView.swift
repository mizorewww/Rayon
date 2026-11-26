//
//  SettingsView.swift
//  Rayon (macOS)
//
//  Settings is a sidebar destination. Its categories and their order come from
//  RayonTerminal's ConfigLayout; this file supplies the rows for Rayon's own
//  preferences (General, Connection, About).
//

import AppKit
import RayonModule
import RayonTerminal
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var router = AppRouter.shared
    /// False while Settings is kept out of sight.
    var active = true

    var body: some View {
        GhosttyConfigurationView(
            embedded: true,
            // Each category's page is hosted on its own, so the rows carry the
            // store with them.
            hostSections: [
                ConfigHostSettingsSection(id: "general.appearance", keywords: "appearance dark light mode theme system effects animation background home glow reduce motion") {
                    AppearanceSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "general.sessions", keywords: "open sessions automatically ask before closing confirmation quit") {
                    SessionSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "general.recent", keywords: "recent servers history quick connect commands record remember") {
                    RecentSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "general.sync", keywords: "icloud sync cloud servers identities snippets port forwards credentials devices") {
                    CloudSyncSettings()
                },
                ConfigHostSettingsSection(id: "general.data", keywords: "backup export import restore ssh config openssh archive") {
                    DataBackupSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "connection.ssh", keywords: "ssh timeout connect wait host key known hosts fingerprint") {
                    SSHSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "connection.uuremote", keywords: "uu remote netease remote desktop device account qr login") {
                    UURemoteSettings()
                },
                ConfigHostSettingsSection(id: "connection.monitor", keywords: "monitor refresh interval status") {
                    MonitorSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "terminal.copyOnSelect", keywords: "copy on select selection clipboard pasteboard automatically share remote osc52 programs") {
                    CopyOnSelectSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "about.Rayon", keywords: "version build license source github agreement") {
                    AboutSettings().environmentObject(store)
                },
                ConfigHostSettingsSection(id: "about.acknowledgements", keywords: "acknowledgements credits libraries ghostty") {
                    AcknowledgementSettings().environmentObject(store)
                },
            ],
            navigation: router.settingsNavigation,
            active: active,
            onApplied: { size in
                // One font size: the terminal's Font Size setting also sets the
                // size ⌘+ and ⌘− start from.
                if let size { store.terminalFontSize = Int(size.rounded()) }
            }
        )
    }
}

/// Appearance follows the system unless the user picks Light or Dark.
enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    static let key = "me.mizorewww.rayon.appearance"

    @MainActor
    func apply() {
        switch self {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    @MainActor
    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject var store: RayonStore
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system.rawValue

    var body: some View {
        RXDividedStack {
            RXFormRow("Light or dark", description: "Terminal colors are set under Colors.") {
                RXSegmented(selection: $appearance, options: [
                    .init(AppearancePreference.system.rawValue, "System"),
                    .init(AppearancePreference.light.rawValue, "Light"),
                    .init(AppearancePreference.dark.rawValue, "Dark"),
                ], caps: false)
            }
            SwitchRow(
                "Animate Home",
                description: "A soft glow and drifting dots behind Quick Connect.",
                isOn: Binding(get: { !store.reducedViewEffects }, set: { store.reducedViewEffects = !$0 })
            )
        }
        .onChange(of: appearance) { raw in
            (AppearancePreference(rawValue: raw) ?? .system).apply()
        }
    }
}

private struct SessionSettings: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        RXDividedStack {
            SwitchRow(
                "Show a session when it connects",
                description: "Switch to a terminal as soon as it opens.",
                isOn: $store.openInterfaceAutomatically
            )
            SwitchRow(
                "Ask before closing a session",
                description: "Confirm before closing a connected terminal or quitting.",
                isOn: Binding(get: { !store.disableConformation }, set: { store.disableConformation = !$0 })
            )
        }
    }
}

private struct RecentSettings: View {
    @EnvironmentObject var store: RayonStore
    @AppStorage("me.mizorewww.rayon.maxRecentRecordCount") private var recentLimit = 8

    var body: some View {
        RXDividedStack {
            SwitchRow(
                "Remember recent servers",
                description: "Listed under Quick Connect on Home.",
                isOn: $store.storeRecent
            )
            NumberFieldRow("Number to keep", value: $recentLimit, in: 1 ... 50)
                .disabled(!store.storeRecent)
            SwitchRow(
                "Include Quick Connect commands",
                description: "Also remember user@host commands typed on Home.",
                isOn: $store.saveTemporarySession
            )
            .disabled(!store.storeRecent)
        }
        .onChange(of: recentLimit) { limit in
            store.maxRecentRecordCount = limit
            if store.recentRecord.count > limit {
                store.recentRecord = Array(store.recentRecord.prefix(limit))
            }
        }
    }
}

private struct SSHSettings: View {
    @EnvironmentObject var store: RayonStore
    @State private var installsTerminfo = GhosttyTerminfo.installsAutomatically

    var body: some View {
        RXDividedStack {
            NumberFieldRow(
                "Connection timeout",
                description: "How long to wait for a server before giving up.",
                value: $store.timeout,
                in: 2 ... 30,
                unit: "s"
            )
            SwitchRow(
                "Install Ghostty's terminfo",
                description: "Rayon's terminal is Ghostty. On a server that lacks its terminfo, Rayon adds it to ~/.terminfo once, so programs there use every feature; nothing else on the server changes. When off, or where it cannot be added, sessions run as xterm-256color.",
                isOn: Binding(
                    get: { installsTerminfo },
                    set: { installsTerminfo = $0; GhosttyTerminfo.installsAutomatically = $0 }
                )
            )
            HostKeysRow()
        }
    }
}

/// How many host keys are saved, and a way to start over.
private struct HostKeysRow: View {
    @State private var count = KnownHosts.shared.count

    var body: some View {
        RXFormRow(
            "Saved host keys",
            description: "A server's key is saved the first time you connect; a server that later presents another key is refused. \(count) saved."
        ) {
            Button("Forget All…") {
                UIBridge.requiresConfirmation(
                    message: "Forget all saved host keys?",
                    informative: "The key each server presents on its next connection is saved as its key.",
                    confirmTitle: "Forget All"
                ) { confirmed in
                    guard confirmed else { return }
                    KnownHosts.shared.forgetAll()
                    count = KnownHosts.shared.count
                }
            }
            .buttonStyle(.rx)
            .disabled(count == 0)
        }
        .onAppear { count = KnownHosts.shared.count }
    }
}

/// Terminal, Mouse & Clipboard: the row above Ghostty's copy settings.
private struct CopyOnSelectSettings: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        RXDividedStack {
            SwitchRow(
                "Copy on select",
                description: "Copy text to the clipboard as soon as you finish selecting it.",
                isOn: $store.terminalCopyOnSelect
            )
            .onChange(of: store.terminalCopyOnSelect) { enabled in
                RayonTerminalView.setCopyOnSelect(enabled)
            }
            SwitchRow(
                "Share clipboard with remote programs",
                description: "Programs running on the server may read and write this Mac's clipboard (OSC 52), so a copy in vim or tmux lands here.",
                isOn: $store.terminalClipboardSharing
            )
            .onChange(of: store.terminalClipboardSharing) { enabled in
                RayonTerminalView.setClipboardSharing(enabled)
            }
        }
    }
}

private struct MonitorSettings: View {
    @EnvironmentObject var store: RayonStore
    private let intervals = [5, 10, 15, 30, 60]

    var body: some View {
        RXFormRow("Refresh", description: "How often an open monitor reads the server.") {
            Picker("Refresh", selection: Binding(get: { max(5, store.monitorInterval) }, set: { store.monitorInterval = $0 })) {
                ForEach(intervals, id: \.self) { seconds in
                    Text("Every \(seconds) s").tag(seconds)
                }
                if !intervals.contains(max(5, store.monitorInterval)) {
                    Text("Every \(store.monitorInterval) s").tag(store.monitorInterval)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// The NetEase UU Remote account behind the remote desktop feature.
private struct UURemoteSettings: View {
    @ObservedObject private var account = UURemoteAccount.shared

    var body: some View {
        RXDividedStack {
            RXFormRow(
                "Account",
                description: "Signs the built-in UU Remote client in with QR code, SMS or an imported token."
            ) {
                HStack(spacing: RX.Space.s3) {
                    if account.isLoggedIn {
                        Label(account.nickname.isEmpty ? "Signed in" : account.nickname,
                              systemImage: "person.crop.circle")
                            .lineLimit(1)
                        Button("Manage…") { openAccountSheet() }
                            .buttonStyle(.rx)
                        Button("Sign Out") { account.logout() }
                            .buttonStyle(.rx)
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.rxInkSecondary)
                        Button("Sign In…") { openAccountSheet() }
                            .buttonStyle(.rx)
                    }
                }
            }
            if account.isLoggedIn {
                RXFormRow(
                    "Devices",
                    description: "Desktop devices on this account; add them as servers from the account panel."
                ) {
                    HStack(spacing: RX.Space.s3) {
                        Text(UURemoteAccount.deviceCount(account.desktopDevices.count))
                            .foregroundStyle(.rxInkSecondary)
                        Button("Refresh") {
                            Task { try? await account.refreshDevices() }
                        }
                        .buttonStyle(.rx)
                    }
                }
            }
        }
    }

    @MainActor
    private func openAccountSheet() {
        SheetPresenter.present { dismiss in
            UURemoteAccountSheet(onConnectDesktop: { machineID in
                dismiss()
                AppRouter.shared.openDesktop(machine: machineID)
            }, close: dismiss)
        }
    }
}

private struct AboutSettings: View {
    @State private var document: AboutDocument?

    var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        #if DEBUG
            return "\(short) (\(build)) · Debug"
        #else
            return "\(short) (\(build))"
        #endif
    }

    /// The commit this copy was built from, written in at build time.
    var commit: String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let info = NSDictionary(contentsOf: url),
              let commit = info["GitCommit"] as? String, !commit.isEmpty
        else { return "Unknown" }
        return commit
    }

    var body: some View {
        RXDividedStack {
            RXFormRow("Version") {
                Text(version)
                    .font(.rxBody.monospacedDigit())
                    .foregroundStyle(.rxInkSecondary)
                    .textSelection(.enabled)
            }
            RXFormRow("Build", description: "The git commit this copy was built from; \"-dirty\" when the source had uncommitted changes.") {
                Text(commit)
                    .font(.rxCode)
                    .foregroundStyle(.rxInkSecondary)
                    .textSelection(.enabled)
            }
            RXFormRow("Source code", description: "mizorewww/Rayon on GitHub") {
                Link(destination: URL(string: "https://github.com/mizorewww/Rayon")!) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.rx)
            }
            RXFormRow("Report a problem", description: "Bugs and ideas go to the project's issue tracker.") {
                Link(destination: URL(string: "https://github.com/mizorewww/Rayon/issues")!) {
                    Label("Issues", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.rx)
            }
            RXFormRow("Legal") {
                HStack(spacing: RX.Space.s2) {
                    Button("License…") { document = .license }
                        .buttonStyle(.rx)
                        .fixedSize()
                    Button("Agreement…") { document = .agreement }
                        .buttonStyle(.rx)
                        .fixedSize()
                        .help("End user license agreement")
                }
            }
        }
        .sheet(item: $document) { item in
            LicenseSheet(document: item) { document = nil }
        }
    }
}

private struct AcknowledgementSettings: View {
    var body: some View {
        RXDividedStack {
            RXFormRow("Maintained by", description: "mizorewww") {
                EmptyView()
            }
            RXFormRow("Originally created by", description: "Lakr Aream (@Lakr233) with @__oquery, @zlind0, @unixzii, @82flex and @xnth97. This version is not affiliated with or endorsed by them.") {
                EmptyView()
            }
            RXFormRow("Terminal", description: "Ghostty, its configuration catalog and app icon presets (MIT, Ghostty contributors).") {
                EmptyView()
            }
            RXFormRow("Libraries", description: LicenseNotices.bundledLibraries.joined(separator: " · ")) {
                EmptyView()
            }
        }
    }
}

enum AboutDocument: String, Identifiable {
    case license = "LICENSE"
    case agreement = "EULA"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .license: return "License"
        case .agreement: return "End User License Agreement"
        }
    }

    var text: String {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: nil),
              let string = try? String(contentsOf: url, encoding: .utf8)
        else { return "The text could not be loaded." }
        return string
    }
}

struct LicenseSheet: View {
    let document: AboutDocument
    let close: () -> Void

    var body: some View {
        SheetScaffold(document.title) {
            ScrollView {
                Text(document.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.rxInkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RX.Space.s4)
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                    .strokeBorder(Color.rxHairline, lineWidth: 1)
            )
        } footer: {
            Spacer()
            Button("Done", action: close)
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 600)
    }
}

/// First launch: the license in a scroll card, the agree checkbox, Quit and Continue.
struct AgreementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var agreed = false

    var body: some View {
        SheetScaffold("Welcome to Rayon") {
            VStack(alignment: .leading, spacing: RX.Space.s3) {
                ScrollView {
                    Text(AboutDocument.agreement.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.rxInkSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RX.Space.s4)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                        .strokeBorder(Color.rxHairline, lineWidth: 1)
                )
                Toggle("I have read and agree to the license", isOn: $agreed)
                    .rxCheckboxToggle()
                    .font(.rxBody)
            }
        } footer: {
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.rx)
            Spacer()
            Button("Continue") {
                RayonStore.shared.licenseAgreed = true
                dismiss()
            }
            .buttonStyle(.rxPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!agreed)
        }
        .frame(width: 560)
        .interactiveDismissDisabled()
    }
}

/// Backups of the data and of the settings, and the OpenSSH `~/.ssh/config`
/// importer, under Settings -> General -> Data.
private struct DataBackupSettings: View {
    @EnvironmentObject var store: RayonStore
    @State private var statusMessage: String?

    var body: some View {
        RXDividedStack {
            RXFormRow(
                "Backup",
                description: "Servers, identities, snippets, port forwards, folders and known host keys in one file. With passwords and keys, the file is protected by a password."
            ) {
                HStack(spacing: RX.Space.s2) {
                    Button("Export Backup…") {
                        SheetPresenter.present { dismiss in
                            BackupExportSheet { includeSecrets, password in
                                dismiss()
                                if let includeSecrets { exportBackup(includeSecrets: includeSecrets, password: password) }
                            }
                        }
                    }
                    .buttonStyle(.rx)
                    Button("Import Backup…") {
                        importBackup()
                    }
                    .buttonStyle(.rx)
                }
            }
            RXFormRow(
                "Settings",
                description: "Rayon's settings, apart from the data, to bring to another Mac."
            ) {
                HStack(spacing: RX.Space.s2) {
                    Button("Export Settings…") {
                        exportPreferences()
                    }
                    .buttonStyle(.rx)
                    Button("Import Settings…") {
                        importPreferences()
                    }
                    .buttonStyle(.rx)
                }
            }
            RXFormRow(
                "OpenSSH config",
                description: "Import Host entries, IdentityFile keys, and ProxyJump links from ~/.ssh/config or another OpenSSH config file."
            ) {
                Button("Import ~/.ssh/config…") {
                    importSSHConfig()
                }
                .buttonStyle(.rx)
            }
            if let statusMessage {
                HelpText(statusMessage)
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
        UIBridge.openPanel(
            message: message,
            prompt: "Import",
            directory: nil,
            canChooseFiles: true,
            canChooseDirectories: false,
            allowsMultipleSelection: false,
            canCreateDirectories: false,
            showsHiddenFiles: false
        ) { urls in
            if let url = urls.first { action(url) }
        }
    }

    private func exportBackup(includeSecrets: Bool, password: String?) {
        guard let url = savePanel("Export Rayon Backup", name: "Rayon.\(DataBackup.fileExtension)") else { return }
        do {
            try store.exportBackup(to: url, includeSecrets: includeSecrets, password: password)
            statusMessage = "Exported backup to \(url.lastPathComponent)."
        } catch {
            UIBridge.presentError(with: "Could not export backup: \(error.localizedDescription)")
        }
    }

    private func importBackup() {
        chooseFile("Choose a Rayon backup") { url in
            if DataBackup.needsPassword(url) {
                askPassword(for: url)
            } else {
                restoreBackup(url, password: nil)
            }
        }
    }

    private func askPassword(for url: URL, retry: Bool = false) {
        SheetPresenter.present { dismiss in
            BackupPasswordSheet(fileName: url.lastPathComponent, retry: retry) { password in
                dismiss()
                if let password { restoreBackup(url, password: password) }
            }
        }
    }

    private func restoreBackup(_ url: URL, password: String?) {
        do {
            let contents = try DataBackup.read(url, password: password)
            let result = store.restore(contents)
            statusMessage = "Imported \(result.machines) servers, \(result.identities) identities, \(result.snippets) snippets, and \(result.forwards) port forwards."
        } catch BackupError.wrongPassword {
            askPassword(for: url, retry: true)
        } catch {
            UIBridge.presentError(with: "Could not import backup: \(error.localizedDescription)")
        }
    }

    private func exportPreferences() {
        guard let url = savePanel("Export Rayon Settings", name: "Rayon.\(PreferencesBackup.fileExtension)") else { return }
        do {
            try PreferencesBackup.export(to: url)
            statusMessage = "Exported settings to \(url.lastPathComponent)."
        } catch {
            UIBridge.presentError(with: "Could not export settings: \(error.localizedDescription)")
        }
    }

    private func importPreferences() {
        chooseFile("Choose exported Rayon settings") { url in
            do {
                try PreferencesBackup.restore(from: url)
                store.reloadPreferences()
                AppearancePreference.applyStored()
                statusMessage = "Imported settings. The terminal's take effect when Rayon opens next."
            } catch {
                UIBridge.presentError(with: "Could not import settings: \(error.localizedDescription)")
            }
        }
    }

    private func importSSHConfig() {
        let sshDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        UIBridge.openPanel(
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
                UIBridge.presentError(with: "Could not read \(url.lastPathComponent) as UTF-8 text.")
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
                        .onSubmit { if !password.isEmpty { onComplete(password) } }
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

/// iCloud sync: on or off, and which kinds of records go.
private struct CloudSyncSettings: View {
    @ObservedObject var sync = CloudSyncModel.shared

    var body: some View {
        RXDividedStack {
            SwitchRow(
                "Sync with iCloud",
                description: sync.preferences.isOn ? sync.statusText : "Keep your data the same on every device signed in to your iCloud account. Passwords and keys travel end-to-end encrypted.",
                isOn: $sync.preferences.isOn
            )
            Group {
                SwitchRow("Servers", description: "With their folders.", isOn: $sync.preferences.servers)
                SwitchRow("Identities", description: "Including passwords and private keys.", isOn: $sync.preferences.identities)
                SwitchRow("Snippets", isOn: $sync.preferences.snippets)
                SwitchRow("Port forwards", isOn: $sync.preferences.portForwards)
            }
            .disabled(!sync.preferences.isOn)
        }
    }
}
