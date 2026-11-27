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
            guard let url = URL(string: "shareddocuments://" + documents.path),
                  UIApplication.shared.canOpenURL(url)
            else {
                Indicator.error("The Files app is not installed.")
                return
            }
            UIApplication.shared.open(url)
        }
    }
#endif
