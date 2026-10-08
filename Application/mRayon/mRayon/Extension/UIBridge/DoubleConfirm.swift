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
    /// a verb on the confirming button and Cancel.
    static func requiresConfirmation(
        message: String,
        informative: String? = nil,
        confirmTitle: String = "Continue",
        destructive: Bool = true,
        confirmation: @escaping (Bool) -> Void
    ) {
        if RayonStore.shared.disableConformation {
            confirmation(true)
            return
        }
        let alert = UIAlertController(title: message, message: informative, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            confirmation(false)
        }))
        alert.addAction(UIAlertAction(title: confirmTitle, style: destructive ? .destructive : .default, handler: { _ in
            confirmation(true)
        }))
        UIWindow.shutUpKeyWindow?.topMostViewController?.present(alert, animated: true, completion: nil)
    }
}
