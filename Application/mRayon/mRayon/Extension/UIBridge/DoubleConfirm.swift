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
        /// Ask even when confirmations are turned off: for losing unsaved work.
        always: Bool = false,
        confirmation: @escaping (Bool) -> Void
    ) {
        nonisolated(unsafe) let confirmation = confirmation
        onMainThread {
            MainActor.assumeIsolated {
                if RayonStore.shared.disableConformation, !always {
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
    }
}

/// Asks before a server's host key is trusted. A changed key is a warning:
/// replacing the saved key is the destructive choice, Cancel the safe one.
final class IOSHostKeyTrustHandler: HostKeyTrustHandler {
    @MainActor func confirm(_ question: HostKeyQuestion) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: question.title, message: question.message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            let trust = UIAlertAction(title: question.confirmTitle, style: question.saved == nil ? .default : .destructive) { _ in
                continuation.resume(returning: true)
            }
            alert.addAction(trust)
            if question.saved == nil { alert.preferredAction = trust }
            guard let presenter = UIWindow.shutUpKeyWindow?.topMostViewController else {
                continuation.resume(returning: false)
                return
            }
            presenter.present(alert, animated: true)
        }
    }
}
