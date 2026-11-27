//
//  AppearancePreference.swift
//  Rayon
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Appearance follows the system unless the user picks Light or Dark. It
/// stays on this device: a Mac and a phone may want different ones.
enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    static let key = "me.mizorewww.rayon.appearance"

    @MainActor
    func apply() {
        #if os(macOS)
            switch self {
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            case .system: NSApp.appearance = nil
            }
        #else
            let style: UIUserInterfaceStyle = switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
            for scene in UIApplication.shared.connectedScenes {
                for window in (scene as? UIWindowScene)?.windows ?? [] {
                    window.overrideUserInterfaceStyle = style
                }
            }
        #endif
    }

    @MainActor
    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}
