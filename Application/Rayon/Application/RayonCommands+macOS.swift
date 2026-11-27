//
//  RayonCommands+macOS.swift
//  Rayon
//
//  The Mac's app and window commands: Settings, new servers and terminals,
//  Close Tab, the sidebar's places and the remote desktop in front.
//

#if os(macOS)
    import AppKit
    import Combine
    import RayonModule
    import SwiftUI

    struct MacAppCommands: Commands {
        /// The terminal's ⌘1…⌘9 pick its tabs, so the places give them up.
        let terminalInFront: Bool
        @ObservedObject private var router = AppRouter.shared
        @ObservedObject private var desktops = RemoteDesktopManager.shared

        var body: some Commands {
            if UpdateManager.shared.canCheckForUpdates {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { Task { await checkForUpdates() } }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppRouter.shared.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Server…") { AppRouter.shared.presentNewServer = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Terminal") { AppRouter.shared.newTerminal() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Local Terminal") { AppRouter.shared.openLocalTerminal(another: true) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("Open Terminals…") { AppRouter.shared.openTerminals() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            if router.route.isSession {
                CommandGroup(replacing: .saveItem) {
                    Button("Close Tab") { AppRouter.shared.closeTabInFront() }
                        .keyboardShortcut("w", modifiers: .command)
                }
            }
            if let desktop = router.desktopInFront {
                CommandMenu("Desktop") {
                    DesktopCommands(session: desktop)
                }
            }
            CommandGroup(after: .sidebar) {
                place("Home", .home, key: "1")
                place("Dashboard", .dashboard, key: "2")
                place("Servers", .servers, key: "3")
                place("Identities", .identities, key: "4")
                place("Snippets", .snippets, key: "5")
                place("Port Forward", .portForward, key: "6")
                place("Remote Desktop", .desktops, key: "7")
                Divider()
            }
        }

        @MainActor private func checkForUpdates() async {
            let manager = UpdateManager.shared
            do {
                guard let package = try await manager.availableUpdate() else {
                    UIBridge.alert(message: "Rayon is up to date", informative: "Version \(manager.currentVersion) is the latest release.")
                    return
                }
                UIBridge.alert(
                    message: "Rayon \(package.version) is available",
                    informative: "You are running version \(manager.currentVersion).",
                    buttons: ["Download", "Later"]
                ) { index, _ in
                    if index == 0 { UIBridge.open(url: package.downloadURL) }
                }
            } catch {
                Logger.app.errorFile("update check failed: \(error.localizedDescription)")
                UIBridge.alert(message: "Unable to check for updates", informative: error.localizedDescription)
            }
        }

        private func place(_ title: String, _ route: Route, key: KeyEquivalent) -> some View {
            Button(title) { AppRouter.shared.route = route }
                .keyboardShortcut(terminalInFront ? nil : KeyboardShortcut(key, modifiers: .command))
        }
    }

    private struct DesktopCommands: View {
        let session: RemoteDesktopSession
        @StateObject private var state: DesktopMenuState

        init(session: RemoteDesktopSession) {
            self.session = session
            _state = StateObject(wrappedValue: DesktopMenuState(session))
        }

        var body: some View {
            let connected = state.connected
            Button("Send Ctrl+Alt+Delete") { session.sendKeys(RemoteDesktopSpecialKeys.ctrlAltDelete) }
                .disabled(!connected || state.viewOnly)
            Button("Paste Clipboard to Remote") {
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    session.pushClipboard(text)
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(!connected)
            Button("Copy Remote Clipboard") {
                UIBridge.sendPasteboard(str: session.remoteClipboard)
            }
            .disabled(!state.hasRemoteClipboard)
            Divider()
            Toggle("View Only", isOn: Binding(get: { state.viewOnly }, set: { session.viewOnly = $0 }))
            Button("Refresh Screen") { session.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!connected)
            Divider()
            if state.ended {
                Button("Reconnect") { session.connect() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            } else {
                Button("Disconnect") { session.disconnect() }
            }
        }
    }

    @MainActor
    private final class DesktopMenuState: ObservableObject {
        @Published private(set) var connected = false
        @Published private(set) var ended = false
        @Published private(set) var viewOnly = false
        @Published private(set) var hasRemoteClipboard = false
        private var watchers: Set<AnyCancellable> = []

        init(_ session: RemoteDesktopSession) {
            session.$phase
                .map { $0 == .connected }
                .removeDuplicates()
                .sink { [weak self] in self?.connected = $0 }
                .store(in: &watchers)
            session.$phase
                .map { $0.isTerminal || $0 == .idle }
                .removeDuplicates()
                .sink { [weak self] in self?.ended = $0 }
                .store(in: &watchers)
            session.$viewOnly
                .removeDuplicates()
                .sink { [weak self] in self?.viewOnly = $0 }
                .store(in: &watchers)
            session.$remoteClipboard
                .map { !$0.isEmpty }
                .removeDuplicates()
                .sink { [weak self] in self?.hasRemoteClipboard = $0 }
                .store(in: &watchers)
        }
    }
#endif
