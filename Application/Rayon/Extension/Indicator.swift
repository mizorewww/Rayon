//
//  Indicator.swift
//  Rayon
//
//  Alerts, confirmations and text input on AlertController, toasts on
//  SPIndicator, as FlowDown's Indicator does. Every call presents over the
//  app's frontmost window; nothing is queued or polled.
//

import AlertController
import RayonDesign
import RayonModule
import SwiftUI
#if os(iOS)
    import SPIndicator
#endif

@MainActor
enum Indicator {
    private struct Action {
        let title: String
        let accent: Bool
        let run: @MainActor () -> Void
    }

    /// AlertController draws its buttons in Rayon's accent, not its own red,
    /// which would make every OK look destructive.
    static func configure() {
        #if os(macOS)
            AlertControllerConfiguration.accentColor = NSColor(Color.rxAccent)
        #else
            AlertControllerConfiguration.accentColor = UIColor(Color.rxAccent)
        #endif
    }

    /// Shows the whole message: a reason cut short cannot be acted on.
    static func error(_ message: String) {
        Logger.app.errorFile("presented error: \(private: message)")
        show(title: "Error", message: message, actions: [Action(title: "OK", accent: true) {}], dismissible: true)
    }

    static func alert(_ title: String, message: String = "") {
        show(title: title, message: message, actions: [Action(title: "OK", accent: true) {}], dismissible: true)
    }

    /// Asks before an action: the title names the thing, the message says the
    /// consequence, the confirming button says the verb.
    /// - Parameter always: ask even when confirmations are turned off, for
    ///   losing unsaved work.
    static func confirm(
        message: String,
        informative: String? = nil,
        confirmTitle: String = "Continue",
        always: Bool = false,
        confirmation: @escaping (Bool) -> Void
    ) {
        if !AppSettings.confirmsClosingSession.value, !always {
            confirmation(true)
            return
        }
        show(title: message, message: informative ?? "", actions: [
            Action(title: "Cancel", accent: false) { confirmation(false) },
            Action(title: confirmTitle, accent: true) { confirmation(true) },
        ], dismissible: false)
    }

    /// Asks before a server's host key is trusted. A changed key is a
    /// warning whose default answer is Cancel.
    static func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
        await withCheckedContinuation { continuation in
            let warning = question.isWarning
            show(title: question.title, message: question.message, actions: [
                Action(title: "Cancel", accent: warning) { continuation.resume(returning: .declined) },
                Action(title: question.confirmTitle, accent: !warning) { continuation.resume(returning: .trusted) },
            ], dismissible: false)
        }
    }

    static func input(
        title: String,
        message: String = "",
        placeholder: String,
        text: String,
        completion: @escaping @MainActor (String) -> Void
    ) {
        present(AlertInputViewController(
            title: .init(title),
            message: .init(message),
            placeholder: .init(placeholder),
            text: text,
            doneButtonText: "OK",
            onConfirm: completion
        ))
    }

    #if os(iOS)
        static func success(_ title: String, message: String? = nil) {
            SPIndicator.present(title: title, message: message, preset: .done, haptic: .success)
        }
    #endif

    private static func show(title: String, message: String, actions: [Action], dismissible: Bool) {
        #if os(macOS)
            guard presenter != nil else { return runModal(title: title, message: message, actions: actions) }
        #endif
        present(AlertViewController(title: .init(title), message: .init(message)) { context in
            if dismissible { context.allowSimpleDispose() }
            for action in actions {
                context.addAction(title: .init(action.title), attribute: action.accent ? .accent : .normal) {
                    context.dispose { action.run() }
                }
            }
        })
    }

    #if os(iOS)
        private static func present(_ alert: AlertViewController) {
            ModalPresenter.present(alert)
        }
    #else
        /// The key window, which is a sheet's own window while one is up.
        private static var presenter: NSViewController? {
            let window = NSApp.keyWindow ?? NSApp.mainWindow ?? MainWindow.ordinaryWindows.first(where: \.isVisible)
            return window?.contentViewController
        }

        private static func present(_ alert: AlertViewController) {
            guard let presenter else { return }
            presenter.present(alert, animated: true)
        }

        /// With no window open (the menu bar only), an app-modal alert is
        /// all the Mac can show.
        private static func runModal(title: String, message: String, actions: [Action]) {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            // NSAlert's first button is its default one.
            let ordered = actions.filter(\.accent) + actions.filter { !$0.accent }
            for action in ordered {
                alert.addButton(withTitle: action.title)
            }
            NSApp.activate()
            let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if ordered.indices.contains(index) { ordered[index].run() }
        }
    #endif
}

/// Answers RayonModule's host-key questions with Indicator.
final class HostKeyTrustPrompt: HostKeyTrustHandler {
    @MainActor func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
        await Indicator.confirm(question)
    }
}
