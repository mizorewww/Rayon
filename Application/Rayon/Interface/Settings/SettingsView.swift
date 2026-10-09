//
//  SettingsView.swift
//  Rayon (macOS)
//
//  Settings is a sidebar destination with its own category column: Rayon's own
//  preferences (General, About), then the terminal configuration catalog.
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
                ConfigHostSettingsSection(
                    id: SettingsCategory.general,
                    title: "General",
                    icon: "gearshape",
                    keywords: "appearance dark light confirmation ask closing recent record quick connect open sessions ssh timeout monitor refresh interval font size"
                ) { GeneralSettings() },
                ConfigHostSettingsSection(
                    id: SettingsCategory.about,
                    title: "About",
                    icon: "info.circle",
                    keywords: "version build license source github acknowledgements libraries"
                ) { AboutSettings() },
            ],
            selection: $router.settingsSelection
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

private struct GeneralSettings: View {
    @EnvironmentObject var store: RayonStore
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system.rawValue
    @AppStorage("wiki.qaq.rayon.maxRecentRecordCount") private var recentLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s6) {
            RXFormSection {
                RXFormRow("Appearance") {
                    RXSegmented(selection: $appearance, options: [
                        .init(AppearancePreference.system.rawValue, "System"),
                        .init(AppearancePreference.light.rawValue, "Light"),
                        .init(AppearancePreference.dark.rawValue, "Dark"),
                    ], caps: false)
                }
            }
            RXFormSection("Behavior") {
                SwitchRow(
                    "Ask before closing",
                    isOn: Binding(get: { !store.disableConformation }, set: { store.disableConformation = !$0 })
                )
                SwitchRow(
                    "Remember recent servers",
                    isOn: $store.storeRecent
                )
                NumberFieldRow(
                    "Recent items to keep",
                    value: $recentLimit,
                    in: 1 ... 50
                )
                .disabled(!store.storeRecent)
                SwitchRow(
                    "Record Quick Connect commands",
                    isOn: $store.saveTemporarySession
                )
                SwitchRow(
                    "Open sessions when connected",
                    isOn: $store.openInterfaceAutomatically
                )
            }
            RXFormSection("Connection") {
                NumberFieldRow(
                    "SSH timeout",
                    description: "How long to wait for a server before giving up.",
                    value: $store.timeout,
                    in: 2 ... 30,
                    unit: "s"
                )
                RXFormRow("Monitor refresh", description: "How often an open monitor reads the server.") {
                    Picker("Monitor refresh", selection: Binding(get: { max(5, store.monitorInterval) }, set: { store.monitorInterval = $0 })) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { seconds in
                            Text("Every \(seconds) s").tag(seconds)
                        }
                        if ![5, 10, 15, 30, 60].contains(max(5, store.monitorInterval)) {
                            Text("Every \(store.monitorInterval) s").tag(store.monitorInterval)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                NumberFieldRow(
                    "Terminal font size",
                    description: "Change per session with ⌘+ and ⌘−.",
                    value: $store.terminalFontSize,
                    in: 4 ... 30,
                    unit: "pt"
                )
            }
        }
        .onChange(of: appearance) { raw in
            (AppearancePreference(rawValue: raw) ?? .system).apply()
        }
        .onChange(of: recentLimit) { limit in
            store.maxRecentRecordCount = limit
            if store.recentRecord.count > limit {
                store.recentRecord = Array(store.recentRecord.prefix(limit))
            }
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
        VStack(alignment: .leading, spacing: RX.Space.s6) {
            RXFormSection("Rayon") {
                RXFormRow("Version") {
                    Text(version)
                        .font(.rxBody.monospacedDigit())
                        .foregroundStyle(.rxInkSecondary)
                        .textSelection(.enabled)
                }
                RXFormRow("Source code") {
                    Link(destination: URL(string: "https://github.com/Lakr233/Rayon")!) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
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
            RXFormSection("Acknowledgements") {
                RXFormRow("Made by", description: "Lakr Aream (@Lakr233) with @__oquery, @zlind0, @unixzii, @82flex and @xnth97.") {
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
        .sheet(item: $document) { item in
            LicenseSheet(document: item) { document = nil }
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
