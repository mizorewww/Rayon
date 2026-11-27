//
//  DoubleConfirm+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

#if os(iOS)
import os
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
    @MainActor func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
        await withCheckedContinuation { continuation in
            let answer = AnswerOnce(continuation)
            let alert = UIAlertController(title: question.title, message: question.message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                answer.resume(.declined)
            })
            let trust = UIAlertAction(title: question.confirmTitle, style: question.isWarning ? .destructive : .default) { _ in
                answer.resume(.trusted)
            }
            alert.addAction(trust)
            if !question.isWarning { alert.preferredAction = trust }
            // An alert no window takes was never answered, not turned down.
            PresentationQueue.present(alert, timeout: 30) { presented in
                if !presented { answer.resume(.unanswered) }
            }
        }
    }

    /// Answers once. UIKit dismisses an alert along with its presenter
    /// without calling a handler; the alert's actions, which hold this,
    /// are released then, and the question ends unanswered instead of
    /// waiting forever.
    private final class AnswerOnce: Sendable {
        private let continuation: OSAllocatedUnfairLock<CheckedContinuation<HostKeyAnswer, Never>?>

        init(_ continuation: CheckedContinuation<HostKeyAnswer, Never>) {
            self.continuation = OSAllocatedUnfairLock(initialState: continuation)
        }

        func resume(_ answer: HostKeyAnswer) {
            continuation.withLock { value in
                defer { value = nil }
                return value
            }?.resume(returning: answer)
        }

        deinit {
            resume(.unanswered)
        }
    }
}

#endif
