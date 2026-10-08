//
//  DoubleConfirm.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

import RayonModule
import SwiftUI

extension UIBridge {
    /// ConfirmDialog: the title names the thing, one sentence of consequence,
    /// a verb on the confirming button and Cancel. Skipped when
    /// Settings › General › Ask before closing is off.
    static func requiresConfirmation(
        message: String,
        informative: String? = nil,
        confirmTitle: String = "Continue",
        destructive: Bool = false,
        confirmation: @escaping (Bool) -> Void
    ) {
        // Keep the immediate callback when confirmation is disabled.
        nonisolated(unsafe) let confirmation = confirmation
        if RayonStore.shared.disableConformation {
            confirmation(true)
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        if let informative { alert.informativeText = informative }
        let confirm = alert.addButton(withTitle: confirmTitle)
        confirm.hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancel")
        if let keyWindow = NSApplication.shared.keyWindow {
            let responseHandler: @Sendable (NSApplication.ModalResponse) -> Void = { resp in
                confirmation(resp == .alertFirstButtonReturn)
            }
            alert.beginSheetModal(for: keyWindow, completionHandler: responseHandler)
        } else {
            let resp = alert.runModal()
            confirmation(resp == .alertFirstButtonReturn)
        }
    }
}

/// Bridges RayonModule's shared file-transfer core to AppKit UI.
final class MacFileTransferUIHandler: FileTransferUIHandler {
    func presentError(_ message: String) {
        UIBridge.presentError(with: message)
    }

    func requiresConfirmation(_ message: String, completion: @escaping (Bool) -> Void) {
        UIBridge.requiresConfirmation(message: message, confirmation: completion)
    }

    func autoOpenInterface(_ context: FileTransferContext) {
        AppRouter.shared.route = .transfer(context.id)
    }
}
