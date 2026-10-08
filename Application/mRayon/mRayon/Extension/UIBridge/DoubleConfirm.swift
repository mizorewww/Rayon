//
//  DoubleConfirm.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

import SwiftUI

extension UIBridge {
    static func requiresConfirmation(message: String, confirmation: @escaping (Bool) -> Void) {
        // HIG: alert titles should be clear and succinct; the confirmation
        // question itself is the title rather than an uninformative emoji.
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            confirmation(false)
        }))
        alert.addAction(UIAlertAction(title: "Continue", style: .destructive, handler: { _ in
            confirmation(true)
        }))
        UIWindow.shutUpKeyWindow?.topMostViewController?.present(alert, animated: true, completion: nil)
    }
}
