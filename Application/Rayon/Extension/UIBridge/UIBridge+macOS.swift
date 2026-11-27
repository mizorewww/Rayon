//
//  UIBridge+macOS.swift
//  Rayon
//
//  Native AppKit dialogs, open panels, pasteboard and workspace helpers.
//

#if os(macOS)
    import AppKit
    import RayonModule
    import Foundation

    enum UIBridge {
        static func sendPasteboard(str: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }

        @MainActor static func open(url: URL) {
            NSWorkspace.shared.open(url)
        }

        @MainActor static var sheetParentWindow: NSWindow? {
            if let key = NSApp.keyWindow, !key.className.contains("NSPopover") && !key.className.contains("NSStatusBar") {
                return key
            }
            return MainWindow.ordinaryWindows.first { $0.isVisible }
        }

        @MainActor static func alert(
            message: String,
            informative: String? = nil,
            buttons: [String] = [],
            destructiveFirstButton: Bool = false,
            textField: String? = nil,
            monospacedDetail: String? = nil,
            completion: ((Int, String?) -> Void)? = nil
        ) {
            let alert = NSAlert()
            alert.messageText = message
            if let informative { alert.informativeText = informative }
            for (index, title) in buttons.enumerated() {
                let button = alert.addButton(withTitle: title)
                if index == 0 { button.hasDestructiveAction = destructiveFirstButton }
            }
            var field: NSTextField?
            if let monospacedDetail {
                // Wraps between any two characters, without the hyphens the
                // informative text adds to a fingerprint it breaks.
                let label = NSTextField(wrappingLabelWithString: monospacedDetail)
                label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                label.lineBreakMode = .byCharWrapping
                label.lineBreakStrategy = []
                label.isSelectable = true
                label.preferredMaxLayoutWidth = 220
                label.frame.size = label.fittingSize
                alert.accessoryView = label
            }
            if let textField {
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
                input.stringValue = textField
                alert.accessoryView = input
                alert.window.initialFirstResponder = input
                field = input
            }
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                let text = field?.stringValue
                DispatchQueue.main.async { completion?(index, text) }
            }
            if let parent = sheetParentWindow {
                alert.beginSheetModal(for: parent, completionHandler: finish)
            } else {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    finish(alert.runModal())
                }
            }
        }

        @MainActor static func openPanel(
            message: String?,
            prompt: String?,
            directory: URL?,
            canChooseFiles: Bool,
            canChooseDirectories: Bool,
            allowsMultipleSelection: Bool,
            canCreateDirectories: Bool,
            showsHiddenFiles: Bool,
            completion: @escaping ([URL]) -> Void
        ) {
            let panel = NSOpenPanel()
            if let message { panel.message = message }
            if let prompt { panel.prompt = prompt }
            if let directory { panel.directoryURL = directory }
            panel.canChooseFiles = canChooseFiles
            panel.canChooseDirectories = canChooseDirectories
            panel.allowsMultipleSelection = allowsMultipleSelection
            panel.canCreateDirectories = canCreateDirectories
            panel.showsHiddenFiles = showsHiddenFiles
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                completion(response == .OK ? panel.urls : [])
            }
            if let parent = sheetParentWindow {
                panel.beginSheetModal(for: parent, completionHandler: finish)
            } else {
                finish(panel.runModal())
            }
        }

        @MainActor static func askForInput(title: String, message: String, defaultValue: String, complete: @escaping (String) -> Void) {
            alert(
                message: title,
                informative: message,
                buttons: ["OK", "Cancel"],
                destructiveFirstButton: false,
                textField: defaultValue
            ) { button, text in
                if button == 0, let text { complete(text) }
            }
        }
    }

#endif
