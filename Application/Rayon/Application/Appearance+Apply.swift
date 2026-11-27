//
//  Appearance+Apply.swift
//  Rayon
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import RayonModule

extension Appearance {
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
}
