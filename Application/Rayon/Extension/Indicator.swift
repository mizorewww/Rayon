//
//  Indicator.swift
//  Rayon
//
//  Alerts, confirmations and text input on AlertController, toasts on
//  SPIndicator, as FlowDown's Indicator does. A destructive confirmation
//  and the host-key question use the system alert instead: AlertController
//  has no destructive style, and the Mac shows the fingerprints in a
//  monospaced accessory. Every call presents over the app's frontmost
//  window; nothing is queued or polled.
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

        static var ok: Action { Action(title: String(localized: "OK"), accent: true) {} }
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
        show(title: String(localized: "Error"), message: message, actions: [.ok], dismissible: true)
    }

    static func alert(_ title: LocalizedStringResource, message: LocalizedStringResource? = nil) {
        show(title: String(localized: title), message: message.map { String(localized: $0) } ?? "", actions: [.ok], dismissible: true)
    }

    /// Asks before an action: the title names the thing, the message says the
    /// consequence, the confirming button says the verb.
    /// - Parameter skippable: a session prompt (closing or stopping a session,
    ///   opening another to the same server, quitting), which "Ask before
    ///   closing a session" turns off. Every other confirmation, a delete
    ///   above all, always asks.
    static func confirm(
        message: LocalizedStringResource,
        informative: LocalizedStringResource? = nil,
        confirmTitle: LocalizedStringResource = "Continue",
        destructive: Bool = false,
        skippable: Bool = false,
        confirmation: @escaping (Bool) -> Void
    ) {
        if skippable, !AppSettings.confirmsClosingSession.value {
            confirmation(true)
            return
        }
        let title = String(localized: message)
        let message = informative.map { String(localized: $0) } ?? ""
        let confirmTitle = String(localized: confirmTitle)
        guard !destructive else {
            return systemConfirm(title: title, message: message, confirmTitle: confirmTitle, confirmation: confirmation)
        }
        show(title: title, message: message, actions: [
            Action(title: String(localized: "Cancel"), accent: false) { confirmation(false) },
            Action(title: confirmTitle, accent: true) { confirmation(true) },
        ], dismissible: false)
    }

    static func input(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        placeholder: LocalizedStringResource,
        text: String,
        completion: @escaping @MainActor (String) -> Void
    ) {
        present(AlertInputViewController(
            title: .init(String(localized: title)),
            message: .init(message.map { String(localized: $0) } ?? ""),
            placeholder: .init(String(localized: placeholder)),
            text: text,
            doneButtonText: "OK",
            onConfirm: completion
        ))
    }

    #if os(iOS)
        static func success(_ title: LocalizedStringResource, message: LocalizedStringResource? = nil) {
            SPIndicator.present(title: String(localized: title), message: message.map { String(localized: $0) }, preset: .done, haptic: .success)
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

        private static func systemConfirm(title: String, message: String, confirmTitle: String, confirmation: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: title, message: message.isEmpty ? nil : message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in confirmation(false) })
            alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in confirmation(true) })
            ModalPresenter.present(alert)
        }

        /// Asks before a server's host key is trusted. A changed key is a
        /// warning: replacing the saved key is the destructive choice.
        static func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
            await withCheckedContinuation { continuation in
                let answer = HostKeyAnswerOnce(continuation)
                let alert = UIAlertController(title: question.title, message: question.message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in answer.resume(.declined) })
                let trust = UIAlertAction(title: question.confirmTitle, style: question.isWarning ? .destructive : .default) { _ in
                    answer.resume(.trusted)
                }
                alert.addAction(trust)
                if !question.isWarning { alert.preferredAction = trust }
                ModalPresenter.present(alert)
            }
        }
    #else
        /// The frontmost window, or the sheet on it: a sheet begun on a
        /// window that already has one would wait for that one to close.
        private static var window: NSWindow? {
            var window = NSApp.keyWindow ?? NSApp.mainWindow ?? MainWindow.ordinaryWindows.first(where: \.isVisible)
            while let sheet = window?.attachedSheet {
                window = sheet
            }
            return window
        }

        private static var presenter: NSViewController? {
            window?.contentViewController
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

        private static func systemConfirm(title: String, message: String, confirmTitle: String, confirmation: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: confirmTitle).hasDestructiveAction = true
            alert.addButton(withTitle: String(localized: "Cancel"))
            Task {
                confirmation(await ask(alert) == .alertFirstButtonReturn)
            }
        }

        /// Asks before a server's host key is trusted. A changed key is a
        /// warning whose default answer is Cancel.
        static func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
            let alert = NSAlert()
            alert.messageText = question.title
            alert.informativeText = question.explanation
            alert.accessoryView = monospacedLabel(question.keys)
            let warning = question.isWarning
            // NSAlert's first button is its default one.
            let cancel = String(localized: "Cancel")
            for title in warning ? [cancel, question.confirmTitle] : [question.confirmTitle, cancel] {
                alert.addButton(withTitle: title)
            }
            alert.buttons[warning ? 1 : 0].hasDestructiveAction = warning
            switch await ask(alert) {
            case warning ? .alertSecondButtonReturn : .alertFirstButtonReturn: return .trusted
            case warning ? .alertFirstButtonReturn : .alertSecondButtonReturn: return .declined
            default: return .unanswered
            }
        }

        /// Wraps between any two characters, without the hyphens the
        /// informative text adds to a fingerprint it breaks.
        private static func monospacedLabel(_ text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.lineBreakMode = .byCharWrapping
            label.lineBreakStrategy = []
            label.isSelectable = true
            label.preferredMaxLayoutWidth = 220
            label.frame.size = label.fittingSize
            return label
        }

        /// Shows the alert as a sheet on the frontmost window. A window
        /// that closes under it ends the sheet with `.abort`, so the
        /// caller always gets an answer.
        private static func ask(_ alert: NSAlert) async -> NSApplication.ModalResponse {
            guard let window else {
                NSApp.activate()
                return alert.runModal()
            }
            let closing = Task {
                for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                    window.endSheet(alert.window, returnCode: .abort)
                    return
                }
            }
            defer { closing.cancel() }
            return await alert.beginSheetModal(for: window)
        }
    #endif
}

/// Answers RayonModule's host-key questions with Indicator.
final class HostKeyTrustPrompt: HostKeyTrustHandler {
    @MainActor func confirm(_ question: HostKeyQuestion) async -> HostKeyAnswer {
        await Indicator.confirm(question)
    }
}
