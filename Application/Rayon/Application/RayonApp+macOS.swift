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
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            MainView()
                .onAppear {
                    AppRouter.shared.openWindow = openWindow
                    if let problem = RayonStore.shared.launchProblem { Indicator.error(problem) }
                    if let notice = RayonStore.shared.takeMigrationNotice() {
                        Indicator.alert("Imported from the Previous Version", message: "\(notice)")
                    }
                }
        }
    }

    enum MainWindow {
        static let minimumSize = CGSize(width: 940, height: 600)

        /// The main windows: not Settings, popovers or the status bar's.
        @MainActor static var ordinaryWindows: [NSWindow] {
            NSApp.windows.filter { window in
                window.canBecomeMain && !window.className.contains("NSPopover") && !window.className.contains("NSStatusBar")
                    && !SettingsWindow.contains(window)
            }
        }

        /// A sheet, a modal panel or an alert is up: the window's own
        /// shortcuts wait for it.
        @MainActor static var isShowingSheetOrModal: Bool {
            if NSApp.modalWindow != nil { return true }
            return ordinaryWindows.contains { window in
                window.attachedSheet != nil || window.contentViewController?.presentedViewControllers?.isEmpty == false
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
            TitleBarDoubleClick.install()
            installWindowPolicyObservers()
            MenubarTool.shared.restore()
            updateActivationPolicy()

            #if DEBUG
                runPreviewHooks()
            #endif
        }

        func applicationWillTerminate(_: Notification) {
            // A setting changed just before ⌘Q is still waiting out its pause.
            TerminalSettings.shared.flush()
            if relaunches {
                // Two instances must never share the store, CloudKit, the
                // status item or UU sessions, and this one is still running
                // here. The shell outlives it, waits for it to exit, and only
                // then opens the new one.
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = [
                    "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open -n "$2""#,
                    "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
                ]
                do { try relaunch.run() } catch { Logger.app.errorFile("relaunch failed: \(error)") }
            }
        }

        /// Set by a restart and cleared if the quit is declined: the next
        /// instance opens once this one has exited.
        private var relaunches = false

        /// Quits, asking first as ⌘Q does, and opens Rayon again.
        func restart() {
            relaunches = true
            NSApp.terminate(nil)
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
            let hasVisibleWindow = (MainWindow.ordinaryWindows + NSApp.windows.filter(SettingsWindow.contains))
                .contains { $0.isVisible || $0.isMiniaturized }
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
                let first = [menu.items.first, menu.item(withTitle: String(localized: "Terminal"))].compactMap(\.?.submenu)
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
                if MainWindow.isShowingSheetOrModal { return true }
                let window = event.window ?? NSApp.keyWindow
                guard let window, MainWindow.ordinaryWindows.contains(window) else { return false }
                if event.isARepeat { return true }
                AppRouter.shared.newTerminal()
                return true
            case "w":
                if MainWindow.isShowingSheetOrModal { return true }
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
            if quitAsked, MainWindow.isShowingSheetOrModal {
                return .terminateCancel
            }
            quitAsked = false

            let terminals = !TerminalManager.shared.sessionContexts.isEmpty
            let kept = TerminalManager.shared.sessionContexts.filter(\.machine.isUURemoteDevice).count
            let terminalConsequence = switch kept {
            case 0: String(localized: "Open terminal sessions will be closed.")
            case TerminalManager.shared.sessionContexts.count: String(localized: "UU Remote sessions keep running on their devices, to resume next time.")
            default: String(localized: "SSH sessions will be closed; UU Remote sessions keep running on their devices, to resume next time.")
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
                unsaved ? String(localized: "Unsaved changes in the editor will be lost.") : nil,
                terminals ? terminalConsequence : nil,
            ]
            quitAsked = true
            Indicator.confirm(
                message: "Quit Rayon?",
                informative: "\(consequences.compactMap { $0 }.joined(separator: " "))",
                confirmTitle: unsaved ? "Discard Changes and Quit" : "Quit",
                destructive: true,
                skippable: !unsaved
            ) { confirmed in
                MainActor.assumeIsolated {
                    self.quitAsked = false
                    guard confirmed else {
                        self.relaunches = false
                        return
                    }
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
