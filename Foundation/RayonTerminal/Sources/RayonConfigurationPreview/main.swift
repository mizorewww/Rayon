import SwiftUI
import RayonTerminal

/// Standalone native preview for UI verification, separate from Rayon's account storage.
@main
struct ConfigurationPreviewApp: App {
    var body: some Scene {
        WindowGroup("Rayon Configuration Preview") { GhosttyConfigurationView() }
            .defaultSize(width: 1280, height: 820)
    }
}
