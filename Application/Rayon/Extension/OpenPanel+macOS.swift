//
//  OpenPanel+macOS.swift
//  Rayon
//

#if os(macOS)
    import AppKit

    @MainActor
    enum OpenPanel {
        /// An open panel, as a sheet on the key window when there is one.
        static func present(
            message: LocalizedStringResource?,
            prompt: LocalizedStringResource?,
            directory: URL?,
            canChooseFiles: Bool,
            canChooseDirectories: Bool,
            allowsMultipleSelection: Bool,
            canCreateDirectories: Bool,
            showsHiddenFiles: Bool,
            completion: @escaping ([URL]) -> Void
        ) {
            let panel = NSOpenPanel()
            if let message { panel.message = String(localized: message) }
            if let prompt { panel.prompt = String(localized: prompt) }
            if let directory { panel.directoryURL = directory }
            panel.canChooseFiles = canChooseFiles
            panel.canChooseDirectories = canChooseDirectories
            panel.allowsMultipleSelection = allowsMultipleSelection
            panel.canCreateDirectories = canCreateDirectories
            panel.showsHiddenFiles = showsHiddenFiles
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                completion(response == .OK ? panel.urls : [])
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    }
#endif
