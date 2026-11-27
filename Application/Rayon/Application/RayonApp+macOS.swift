//
//  RayonApp+macOS.swift
//  Rayon
//

#if os(macOS)
    import AppKit
    import Combine
    import RayonModule
    import RayonTerminal
    import SwiftUI

    extension RayonApp {
        /// The Mac's answers to the dialogs RayonModule asks for.
        @MainActor static func installPlatformHandlers() {
            PortForwardBackend.shared.onError = { Indicator.error($0) }
            FileTransferInterface.uiHandler = MacFileTransferUIHandler()
            HostKeyTrust.handler = HostKeyTrustPrompt()
        }
    }

    /// The main window: the sidebar and the page it routes to.
    struct RootView: View {
        var body: some View {
            MainView()
                .onAppear {
                    if let problem = RayonStore.shared.launchProblem { Indicator.error(problem) }
                }
        }
    }

    enum MainWindow {
        static let minimumSize = CGSize(width: 940, height: 600)

        @MainActor static var ordinaryWindows: [NSWindow] {
            NSApp.windows.filter { window in
                window.canBecomeMain && !window.className.contains("NSPopover") && !window.className.contains("NSStatusBar")
            }
        }

        @MainActor static func show() {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let window = ordinaryWindows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @MainActor
    class AppDelegate: NSObject, NSApplicationDelegate {
        private(set) static var shared: AppDelegate!
        private var shortcutMonitor: Any?
        private var windowObservers: [NSObjectProtocol] = []

        override init() {
            super.init()
            AppDelegate.shared = self
        }

        func applicationDidFinishLaunching(_: Notification) {
            SettingsEffects.start()
            installShortcutMonitor()
            installWindowPolicyObservers()
            MenubarTool.shared.restore()
            updateActivationPolicy()

            #if DEBUG
                runPreviewHooks()
            #endif
        }

        private func installWindowPolicyObservers() {
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.willCloseNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in names {
                windowObservers.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.updateActivationPolicy()
                        }
                    }
                )
            }
        }

        func updateActivationPolicy() {
            guard !terminating else { return }
            let hasVisibleWindow = MainWindow.ordinaryWindows.contains { $0.isVisible || $0.isMiniaturized }
            let accessory = !hasVisibleWindow && MenubarTool.shared.hasCat
            let policy: NSApplication.ActivationPolicy = accessory ? .accessory : .regular
            if NSApp.activationPolicy() != policy {
                NSApp.setActivationPolicy(policy)
            }
        }

        private func installShortcutMonitor() {
            guard shortcutMonitor == nil else { return }
            shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handleShortcut(event) else { return event }
                return nil
            }
        }

        private func handleShortcut(_ event: NSEvent) -> Bool {
            // The terminal view sees key equivalents before the menu bar and
            // claims Ghostty's own bindings for them (⌘D splits, ⌘1 goes to a
            // tab, ⌘+ resizes one surface, ⌘, opens its config), which Rayon
            // does itself. The app menu's and the Terminal menu's shortcuts
            // get the first chance instead; Edit's stay with the terminal.
            if event.modifierFlags.contains(.command), NSApp.modalWindow == nil,
               let window = event.window, MainWindow.ordinaryWindows.contains(window),
               let menu = NSApp.mainMenu
            {
                let first = [menu.items.first, menu.item(withTitle: "Terminal")].compactMap(\.?.submenu)
                if first.contains(where: { $0.performKeyEquivalent(with: event) }) { return true }
            }
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                  NSApp.modalWindow == nil
            else { return false }
            let key: String
            switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased()) {
            case (12, _), (_, "q"): key = "q"
            case (13, _), (_, "w"): key = "w"
            case (17, _), (_, "t"): key = "t"
            default: return false
            }
            switch key {
            case "q":
                NSApp.terminate(nil)
                return true
            case "t":
                if RayonUtil.isShowingSheetOrModal { return true }
                let window = event.window ?? NSApp.keyWindow
                guard let window, MainWindow.ordinaryWindows.contains(window) else { return false }
                if event.isARepeat { return true }
                AppRouter.shared.newTerminal()
                return true
            case "w":
                if RayonUtil.isShowingSheetOrModal { return true }
                let window = event.window ?? NSApp.keyWindow
                guard let window, MainWindow.ordinaryWindows.contains(window) else { return false }
                if event.isARepeat { return true }
                AppRouter.shared.closeTabInFront()
                return true
            default:
                return false
            }
        }

        private var quitConfirmed = false
        private var quitAsked = false
        private var terminating = false

        func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
            if quitConfirmed {
                terminating = true
                return .terminateNow
            }
            if quitAsked, RayonUtil.isShowingSheetOrModal {
                return .terminateCancel
            }
            quitAsked = false

            let terminals = !TerminalManager.shared.sessionContexts.isEmpty
            let kept = TerminalManager.shared.sessionContexts.filter(\.machine.isUURemoteDevice).count
            let terminalConsequence = switch kept {
            case 0: "Open terminal sessions will be closed."
            case TerminalManager.shared.sessionContexts.count: "UU Remote sessions keep running on their devices, to resume next time."
            default: "SSH sessions will be closed; UU Remote sessions keep running on their devices, to resume next time."
            }
            let unsaved = EditorCenter.shared.workspaces.contains(where: \.hasUnsavedChanges)
            Logger.app.infoFile("quit requested: terminals \(terminals), unsaved \(unsaved)")
            guard terminals || unsaved else {
                terminating = true
                return .terminateNow
            }
            if !AppSettings.confirmsClosingSession.value, !unsaved {
                terminating = true
                TerminalManager.shared.closeAll()
                return .terminateNow
            }
            let consequences = [
                unsaved ? "Unsaved changes in the editor will be lost." : nil,
                terminals ? terminalConsequence : nil,
            ]
            quitAsked = true
            Indicator.confirm(
                message: "Quit Rayon?",
                informative: consequences.compactMap { $0 }.joined(separator: " "),
                confirmTitle: unsaved ? "Discard Changes and Quit" : "Quit",
                always: unsaved
            ) { confirmed in
                MainActor.assumeIsolated {
                    self.quitAsked = false
                    guard confirmed else { return }
                    self.quitConfirmed = true
                    self.terminating = true
                    TerminalManager.shared.closeAll()
                    NSApp.terminate(nil)
                }
            }
            return .terminateCancel
        }
    }

#endif
