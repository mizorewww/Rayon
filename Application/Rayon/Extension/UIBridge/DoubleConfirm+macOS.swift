//
//  DoubleConfirm+macOS.swift
//  Rayon
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    extension UIBridge {
        static func requiresConfirmation(
            message: String,
            informative: String? = nil,
            confirmTitle: String = "Continue",
            destructive: Bool = false,
            always: Bool = false,
            confirmation: @escaping (Bool) -> Void
        ) {
            nonisolated(unsafe) let confirmation = confirmation
            onMainThread {
                MainActor.assumeIsolated {
                    if !AppSettings.confirmsClosingSession.value, !always {
                        confirmation(true)
                        return
                    }
                    alert(
                        message: message,
                        informative: informative,
                        buttons: [confirmTitle, "Cancel"],
                        destructiveFirstButton: destructive,
                        textField: nil
                    ) { button, _ in
                        confirmation(button == 0)
                    }
                }
            }
        }
    }

    /// Bridges RayonModule's shared file-transfer core to the Mac app's UI.
    final class MacFileTransferUIHandler: FileTransferUIHandler {
        func presentError(_ message: String) {
            UIBridge.presentError(with: message)
        }

        func requiresConfirmation(_ message: String, completion: @escaping (Bool) -> Void) {
            UIBridge.requiresConfirmation(message: message, confirmation: completion)
        }

        func autoOpenInterface(_ context: FileTransferContext) {
            let id = context.id
            MainActor.assumeIsolated {
                if AppRouter.shared.route == .editor(id) { return }
                AppRouter.shared.route = .transfer(id)
            }
        }
    }

    /// Asks before a server's host key is trusted. A changed key is a warning
    /// whose default answer is Cancel.
    final class MacHostKeyTrustHandler: HostKeyTrustHandler {
        @MainActor func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
            let changed = question.isWarning
            let buttons = changed ? ["Cancel", question.confirmTitle] : [question.confirmTitle, "Cancel"]
            return await withCheckedContinuation { continuation in
                UIBridge.alert(
                    message: question.title,
                    informative: question.explanation,
                    buttons: buttons,
                    destructiveFirstButton: false,
                    monospacedDetail: question.keys
                ) { button, _ in
                    continuation.resume(returning: button == (changed ? 1 : 0) ? .trusted : .declined)
                }
            }
        }
    }

#endif
