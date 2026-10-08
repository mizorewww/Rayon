//
//  DoubleConfirm.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

import RayonModule
import SwiftUI

extension UIBridge {
    static func requiresConfirmation(message: String, confirmation: @escaping (Bool) -> Void) {
        // Keep the immediate callback when confirmation is disabled.
        nonisolated(unsafe) let confirmation = confirmation
        if RayonStore.shared.disableConformation {
            confirmation(true)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.addButton(withTitle: "Confirm")
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
