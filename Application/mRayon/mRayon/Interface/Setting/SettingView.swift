//
//  SettingView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//
//  Settings: the categories as a list, each pushing its groups as cards. The
//  terminal's settings are RayonTerminal's view.
//

import RayonEditor
import RayonModule
import RayonTerminal
import SwiftUI

struct SettingView: View {
    @ObservedObject var store = RayonStore.shared
    @State private var editingConfigFile = false

    private enum Category: String, CaseIterable, Identifiable {
        case general = "General"
        case connection = "Connection"
        case terminal = "Terminal"
        case about = "About"

        var id: Self { self }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .connection: return "network"
            case .terminal: return "terminal"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        List(Category.allCases) { category in
            NavigationLink {
                ScrollView {
                    VStack(alignment: .leading, spacing: RX.Space.s6) {
                        page(category)
                    }
                    .padding(RX.Space.s4)
                }
                .background(RXBackdrop().ignoresSafeArea())
                .navigationTitle(category.rawValue)
            } label: {
                Label(category.rawValue, systemImage: category.icon)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $editingConfigFile) {
            TerminalConfigFileSheet()
        }
    }

    @ViewBuilder
    private func page(_ category: Category) -> some View {
        switch category {
        case .general:
            SettingsGroup("Appearance") { AppearanceSettings() }
            SettingsGroup("Sessions") { SessionSettings() }
            SettingsGroup("Recent") { RecentSettings() }
            SettingsGroup("iCloud Sync") { CloudSyncSettings() }
            SettingsGroup("Data") { DataSettings() }
        case .connection:
            SettingsGroup("SSH") { SSHSettings() }
            SettingsGroup("Monitor") { MonitorSettings() }
        case .terminal:
            GhosttyConfigurationView(
                copyOnSelect: $store.terminalCopyOnSelect,
                clipboardSharing: $store.terminalClipboardSharing,
                openConfigFile: { _ in editingConfigFile = true }
            )
        case .about:
            SettingsGroup("Rayon") { AboutSettings() }
            SettingsGroup("Acknowledgements") { AcknowledgementSettings() }
        }
    }
}

/// A group of Settings: its caption, then its rows on one card.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            CapsLabel(title)
                .padding(.leading, RX.Space.s4)
            content
                .padding(.horizontal, RX.Space.s4)
                .background(Color.clear.rxCard(padding: 0))
        }
    }
}

/// `config.ghostty` in the built-in editor. Saving applies it to every
/// terminal; a file Ghostty rejects is not saved, and the reason is shown.
private struct TerminalConfigFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = RayonTerminalConfiguration.contents
    @State private var issue: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let issue {
                    HelpText(issue, isError: true)
                        .padding(RX.Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                CodeEditor(text: $text, language: .plain)
            }
            .navigationTitle("config.ghostty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try RayonTerminalConfiguration.save(text)
                            dismiss()
                        } catch {
                            issue = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

/// Light or dark, applied to every window of the app.
enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    static let key = "me.mizorewww.rayon.appearance"

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    @MainActor
    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var store = RayonStore.shared
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system.rawValue

    var body: some View {
        RXDividedStack {
            RXFormRow("Light or dark", description: "Terminal colors are set under Terminal.") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag(AppearancePreference.system.rawValue)
                    Text("Light").tag(AppearancePreference.light.rawValue)
                    Text("Dark").tag(AppearancePreference.dark.rawValue)
                }
                .labelsHidden()
                .fixedSize()
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
    @ObservedObject var store = RayonStore.shared

    var body: some View {
        RXDividedStack {
            SwitchRow(
                "Show a session when it connects",
                description: "Open the terminal as soon as it connects.",
                isOn: $store.openInterfaceAutomatically
            )
            SwitchRow(
                "Ask before closing a session",
                description: "Confirm before closing a connected terminal.",
                isOn: Binding(get: { !store.disableConformation }, set: { store.disableConformation = !$0 })
            )
        }
    }
}

private struct RecentSettings: View {
    @ObservedObject var store = RayonStore.shared
    @AppStorage("me.mizorewww.rayon.maxRecentRecordCount") private var recentLimit = 8

    var body: some View {
        RXDividedStack {
            SwitchRow("Remember recent servers", description: "Listed under Quick Connect on Home.", isOn: $store.storeRecent)
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

private struct DataSettings: View {
    #if DEBUG
        @State private var redirectLog = UserDefaults.standard.value(forKey: "me.mizorewww.redirect.diag") as? Bool ?? false
    #endif

    var body: some View {
        RXDividedStack {
            DataBackupRows()
            RXFormRow("App container", description: "Files the app keeps, in the Files app.") {
                Button("Show") { UIBridge.openFileContainer() }
                    .buttonStyle(.rx(size: .small))
            }
            NavigationLink {
                LogView()
            } label: {
                RXFormRow("App log", description: "Diagnostics for reporting a problem.") {
                    Image(systemName: "chevron.right").foregroundStyle(.rxInkTertiary)
                }
            }
            .buttonStyle(.plain)
            #if DEBUG
                SwitchRow(
                    "Redirect log",
                    description: "Takes effect after restarting the app.",
                    isOn: $redirectLog
                )
                .onChange(of: redirectLog) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "me.mizorewww.redirect.diag")
                }
            #endif
        }
    }
}

private struct SSHSettings: View {
    @ObservedObject var store = RayonStore.shared

    var body: some View {
        RXDividedStack {
            NumberFieldRow(
                "Connection timeout",
                description: "How long to wait for a server before giving up.",
                value: $store.timeout,
                in: 2 ... 30,
                unit: "s"
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
                UIBridge.requiresConfirmation(message: "Forget all saved host keys?") { confirmed in
                    guard confirmed else { return }
                    KnownHosts.shared.forgetAll()
                    count = KnownHosts.shared.count
                }
            }
            .buttonStyle(.rx(size: .small))
            .disabled(count == 0)
        }
        .onAppear { count = KnownHosts.shared.count }
    }
}

private struct MonitorSettings: View {
    @ObservedObject var store = RayonStore.shared
    private let intervals = [5, 10, 15, 30, 60]

    var body: some View {
        RXFormRow("Refresh", description: "How often an open monitor reads the server.") {
            Picker("Refresh", selection: Binding(get: { max(5, store.monitorInterval) }, set: { store.monitorInterval = $0 })) {
                ForEach(intervals, id: \.self) { Text("Every \($0) s").tag($0) }
                if !intervals.contains(max(5, store.monitorInterval)) {
                    Text("Every \(store.monitorInterval) s").tag(store.monitorInterval)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        RXDividedStack {
            RXFormRow("Version") {
                Text(appVersion)
                    .font(.rxBody.monospacedDigit())
                    .foregroundStyle(.rxInkSecondary)
            }
            RXFormRow("Source code", description: "mizorewww/Rayon on GitHub") {
                Link("GitHub", destination: URL(string: "https://github.com/mizorewww/Rayon")!)
            }
            RXFormRow("Report a problem") {
                Link("Issues", destination: URL(string: "https://github.com/mizorewww/Rayon/issues")!)
            }
            NavigationLink {
                LicenseView()
            } label: {
                RXFormRow("License") {
                    Image(systemName: "chevron.right").foregroundStyle(.rxInkTertiary)
                }
            }
            .buttonStyle(.plain)
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
            RXFormRow("Terminal", description: "Ghostty and its theme collection (MIT, Ghostty contributors).") {
                EmptyView()
            }
        }
    }
}
