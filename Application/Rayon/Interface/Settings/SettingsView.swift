//
//  SettingsView.swift
//  Rayon (macOS)
//
//  Settings is a sidebar destination. Its categories and their order come from
//  RayonTerminal's ConfigLayout; this file supplies the rows for Rayon's own
//  preferences (General, Connection, About).
//

import RayonModule
import RayonTerminal
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: RayonStore
    @ObservedObject var router = AppRouter.shared

    var body: some View {
        GhosttyConfigurationView(
            embedded: true,
            hostSections: [
                ConfigHostSettingsSection(id: "general.appearance", keywords: "appearance dark light mode theme system") {
                    AppearanceSettings()
                },
                ConfigHostSettingsSection(id: "general.sessions", keywords: "open sessions automatically ask before closing confirmation quit") {
                    SessionSettings()
                },
                ConfigHostSettingsSection(id: "general.recent", keywords: "recent servers history quick connect commands record remember") {
                    RecentSettings()
                },
                ConfigHostSettingsSection(id: "connection.ssh", keywords: "ssh timeout connect wait") {
                    SSHSettings()
                },
                ConfigHostSettingsSection(id: "connection.monitor", keywords: "monitor refresh interval status") {
                    MonitorSettings()
                },
                ConfigHostSettingsSection(id: "about.rayon", keywords: "version build license source github agreement") {
                    AboutSettings()
                },
                ConfigHostSettingsSection(id: "about.acknowledgements", keywords: "acknowledgements credits libraries ghostty") {
                    AcknowledgementSettings()
                },
            ],
            selection: $router.settingsSelection,
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

    static let key = "wiki.qaq.rayon.appearance"

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}

private struct AppearanceSettings: View {
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system.rawValue

    var body: some View {
        RXFormRow("Appearance", description: "Light or dark windows; terminal colors are set under Colors.") {
            RXSegmented(selection: $appearance, options: [
                .init(AppearancePreference.system.rawValue, "System"),
                .init(AppearancePreference.light.rawValue, "Light"),
                .init(AppearancePreference.dark.rawValue, "Dark"),
            ], caps: false)
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
    @AppStorage("wiki.qaq.rayon.maxRecentRecordCount") private var recentLimit = 8

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

    var body: some View {
        NumberFieldRow(
            "Connection timeout",
            description: "How long to wait for a server before giving up.",
            value: $store.timeout,
            in: 2 ... 30,
            unit: "s"
        )
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

    var body: some View {
        RXDividedStack {
            RXFormRow("Version") {
                Text(version)
                    .font(.rxBody.monospacedDigit())
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
            RXFormRow("License") {
                Button("View License…") { document = .license }
                    .buttonStyle(.rx)
            }
            RXFormRow("End user license agreement") {
                Button("View Agreement…") { document = .agreement }
                    .buttonStyle(.rx)
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
            RXFormRow("Maintained by", description: "mizorewww, continuing Rayon after the original repository was archived.") {
                EmptyView()
            }
            RXFormRow("Originally created by", description: "Lakr Aream (@Lakr233) with @__oquery, @zlind0, @unixzii, @82flex and @xnth97. This version is not affiliated with or endorsed by them.") {
                EmptyView()
            }
            RXFormRow("Terminal", description: "Ghostty, its configuration catalog and app icon presets (MIT, Ghostty contributors).") {
                EmptyView()
            }
            RXFormRow("Libraries", description: "libssh2 · NSRemoteShell · CodeMirror · XMLCoder · SymbolPicker · Keychain") {
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
            .background(
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
                .background(
                    RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                        .strokeBorder(Color.rxHairline, lineWidth: 1)
                )
                Toggle("I have read and agree to the license", isOn: $agreed)
                    .toggleStyle(.checkbox)
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
