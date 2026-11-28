//
//  LanguageSettings.swift
//  Rayon
//
//  Settings › General › Language. The system's per-app language is the
//  whole mechanism: on the Mac Rayon writes its own AppleLanguages, the
//  value System Settings › Language & Region › Applications writes, and
//  takes it at the next launch; on the iPhone and iPad only the Settings
//  app sets it, so the row opens Rayon's page there.
//

import SwiftUI

enum AppLanguage {
    /// Rayon's localizations, each in its own name as the system lists them.
    static let all: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja", "日本語"),
        ("fr", "Français"),
        ("es", "Español"),
    ]

    /// The localization a preference list resolves to, as Bundle picks one.
    static func resolve(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: all.map(\.code), forPreferences: preferences).first ?? "en"
    }

    static func name(of code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// The language Rayon shows now.
    static var current: String {
        resolve(Bundle.main.preferredLocalizations)
    }

    #if os(macOS)
        private static let key = "AppleLanguages"

        /// The app's own choice, or nil for the system's: read from the app's
        /// domain alone, as the plain lookup falls back to the global list.
        static var chosen: String? {
            guard let domain = Bundle.main.bundleIdentifier,
                  let languages = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String],
                  !languages.isEmpty
            else { return nil }
            return resolve(languages)
        }

        static func choose(_ code: String?) {
            if let code {
                UserDefaults.standard.set([code], forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        /// What the next launch shows: the choice, or the system's language.
        static var next: String {
            chosen ?? resolve(UserDefaults.standard.stringArray(forKey: key) ?? [])
        }
    #endif
}

struct LanguageSettings: View {
    #if os(macOS)
        @State private var chosen = AppLanguage.chosen
        @State private var restartsFor: String?

        var body: some View {
            Picker(selection: Binding(get: { chosen }, set: choose)) {
                Text("System Default").tag(String?.none)
                Divider()
                ForEach(AppLanguage.all, id: \.code) { language in
                    Text(verbatim: language.name).tag(Optional(language.code))
                }
            } label: {
                Text("Language")
                Text("Takes effect when Rayon restarts.")
            }
            .alert(
                Text("Rayon needs to restart to use \(restartsFor ?? "")."),
                isPresented: Binding(get: { restartsFor != nil }, set: { if !$0 { restartsFor = nil } })
            ) {
                Button("Restart Now") { AppDelegate.shared.restart() }
                Button("Later", role: .cancel) {}
            }
        }

        private func choose(_ code: String?) {
            guard code != chosen else { return }
            AppLanguage.choose(code)
            chosen = code
            restartsFor = AppLanguage.name(of: AppLanguage.next)
        }
    #else
        var body: some View {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                LabeledContent {
                    Text(verbatim: AppLanguage.name(of: AppLanguage.current))
                } label: {
                    Text("Language").foregroundStyle(Color.primary)
                }
            }
        }
    #endif
}
