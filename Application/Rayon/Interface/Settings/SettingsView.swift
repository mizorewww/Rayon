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
                    subtitle: "Rayon's own preferences",
                    icon: "gearshape",
                    keywords: "appearance dark light confirmation ask closing recent record quick connect open sessions ssh timeout monitor refresh interval font size"
                ) { GeneralSettings() },
                ConfigHostSettingsSection(
                    id: SettingsCategory.about,
                    title: "About",
                    subtitle: "Version, source, license and acknowledgements",
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
            RXFormSection("Appearance") {
                RXFormRow("Appearance", description: "Follow the system, or keep Rayon light or dark.") {
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
                    description: "Confirm before closing a running session, deleting or duplicating items.",
                    isOn: Binding(get: { !store.disableConformation }, set: { store.disableConformation = !$0 })
                )
                SwitchRow(
                    "Remember recent servers",
                    description: "Shows recently used servers and Quick Connect commands on Home.",
                    isOn: $store.storeRecent
                )
                NumberFieldRow(
                    "Recent items to keep",
                    description: "Older entries are dropped first.",
                    value: $recentLimit,
                    in: 1 ... 50
                )
                .disabled(!store.storeRecent)
                SwitchRow(
                    "Record Quick Connect commands",
                    description: "Keeps commands you typed so Quick Connect can suggest them.",
                    isOn: $store.saveTemporarySession
                )
                SwitchRow(
                    "Open sessions when connected",
                    description: "Switch to a new terminal or file transfer as soon as it opens.",
                    isOn: $store.openInterfaceAutomatically
                )
            }
            RXFormSection("Connection", footer: "Changes apply immediately.") {
                SliderRow(
                    "SSH timeout",
                    description: "Report a connection as failed after this long (2–30 s).",
                    value: Binding(get: { Double(store.timeout) }, set: { store.timeout = Int($0) }),
                    in: 2 ... 30
                ) { "\(Int($0)) s" }
                SliderRow(
                    "Monitor refresh",
                    description: "Wait this long between reads of a server's status (5–60 s).",
                    value: Binding(get: { Double(max(5, store.monitorInterval)) }, set: { store.monitorInterval = Int($0) }),
                    in: 5 ... 60,
                    step: 5
                ) { "\(Int($0)) s" }
                NumberFieldRow(
                    "Terminal font size",
                    description: "Default size for sessions; change it per session with ⌘+ and ⌘−.",
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
                RXFormRow("Source code", description: "Rayon is open source.") {
                    Link(destination: URL(string: "https://github.com/Lakr233/Rayon")!) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.rx)
                }
                RXFormRow("License", description: "MIT License, Lakr's Edition.") {
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
        SheetScaffold("Welcome to Rayon", lead: "Please read and accept the license to continue.") {
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
