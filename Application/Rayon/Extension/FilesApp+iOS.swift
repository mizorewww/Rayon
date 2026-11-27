//
//  FilesApp+iOS.swift
//  Rayon
//

#if os(iOS)
    import UIKit

    @MainActor
    enum FilesApp {
        /// Opens the app's Documents folder, where downloads land, in Files.
        static func showDocuments() {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            guard let url = URL(string: "shareddocuments://" + documents.path) else { return }
            // Opened without canOpenURL first, which answers false for a
            // scheme the app does not list as one it queries.
            UIApplication.shared.open(url) { opened in
                if !opened { Indicator.error("The Files app is not installed.") }
            }
        }
    }
#endif
