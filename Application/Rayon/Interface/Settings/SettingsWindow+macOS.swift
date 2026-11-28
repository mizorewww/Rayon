//
//  SettingsWindow+macOS.swift
//  Rayon
//
//  Settings' own window, as System Settings and the Mac's other apps have
//  one: ⌘,, Settings… in the app menu and every way into Settings in Rayon
//  open it. The window keeps its size and place, and Settings its page.
//

#if os(macOS)
    import AppKit
    import RayonModule
    import SwiftUI

    struct SettingsWindow: Scene {
        static let id = "settings"

        var body: some Scene {
            Window("Settings", id: Self.id) {
                SettingsView()
                    .environmentObject(RayonStore.shared)
            }
            .windowToolbarStyle(.unified)
            .defaultSize(width: 860, height: 640)
            .windowResizability(.contentMinSize)
            // Settings… in the app menu opens it; the Window menu need not list it too.
            .commandsRemoved()
        }

        /// Whether `window` is the Settings window, by the identifier
        /// SwiftUI gives its scene's window.
        @MainActor static func contains(_ window: NSWindow) -> Bool {
            window.identifier?.rawValue.hasPrefix(id) == true
        }
    }
#endif
