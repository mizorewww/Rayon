//
//  AppRouter+macOS.swift
//  Rayon
//
//  The main window's navigation state and the actions that open sessions.
//

#if os(macOS)
    import Combine
    import MachineStatusView
    import RayonModule
    import RayonTerminal
    import SwiftUI

    enum Route: Hashable {
        case home
        /// Every saved server as a tile.
        case dashboard
        case servers
        case identities
        case snippets
        case portForward
        /// Every server with a remote desktop, and the UU Remote account.
        case desktops
        case terminal(UUID)
        case monitor(UUID)
        case transfer(UUID)
        /// A server's editor, by the id of the SFTP session it works over.
        case editor(UUID)
        /// A server's remote desktop, by the RemoteDesktopSession id.
        case desktop(UUID)
    }

    /// The router and everything it publishes are main-thread state, like the
    /// interface it drives.
    @MainActor
    final class AppRouter: ObservableObject {
        static let shared = AppRouter()

        @Published var route: Route = .home {
            didSet {
                if !route.isSession {
                    lastPlace = route
                } else if let owner = owner(of: route) {
                    lastRoute[owner] = route
                }
            }
        }
        /// The page each server (or Quick Connect terminal) showed last, so its
        /// sidebar row returns to the same tool.
        private var lastRoute: [SessionOwner: Route] = [:]
        /// The last page that is not a session; closing a session returns here.
        private(set) var lastPlace: Route = .home
        @Published var columnVisibility: NavigationSplitViewVisibility = .all
        /// The sheets over the main windows, at most one per window, asked
        /// for from anywhere: a menu, a context menu, a command.
        @Published private(set) var sheets: [WindowSheet] = []
        /// The page Settings shows, kept from one launch to the next.
        /// Settings follows this itself, so a change of page does not go
        /// through every view that watches the router.
        let settingsNavigation = ConfigNavigation(
            UserDefaults.standard.string(forKey: AppRouter.settingsSelectionKey) ?? SettingsCategory.general
        )
        var settingsSelection: String {
            get { settingsNavigation.selection }
            set { settingsNavigation.go(newValue) }
        }

        private static let settingsSelectionKey = "SettingsSelection"
        /// Opens a scene: SwiftUI hands it only to views, so the main
        /// window's root view passes it on when it appears.
        var openWindow: OpenWindowAction?

        private var cancellables = Set<AnyCancellable>()

        private init() {
            settingsNavigation.$selection
                .dropFirst()
                .sink { UserDefaults.standard.set($0, forKey: AppRouter.settingsSelectionKey) }
                .store(in: &cancellables)
            // When a session closes, leave its page.
            leaveWhenSessionEnds(TerminalManager.shared.$sessionContexts) {
                if case let .terminal(id) = $0 { return id }
                return nil
            }
            leaveWhenSessionEnds(MonitorCenter.shared.$sessions) {
                if case let .monitor(id) = $0 { return id }
                return nil
            }
            leaveWhenSessionEnds(FileTransferManager.shared.$transfers) {
                if case let .transfer(id) = $0 { return id }
                return nil
            }
            leaveWhenSessionEnds(EditorCenter.shared.$workspaces) {
                if case let .editor(id) = $0 { return id }
                return nil
            }
            leaveWhenSessionEnds(RemoteDesktopManager.shared.$sessions) {
                if case let .desktop(id) = $0 { return id }
                return nil
            }
        }

        /// Returns to another open session of the same server if one exists,
        /// otherwise to the last non-session place.
        private func leaveWhenSessionEnds<Element: Identifiable>(
            _ publisher: Published<[Element]>.Publisher,
            id routeID: @escaping (Route) -> UUID?
        ) where Element.ID == UUID {
            publisher
                .sink { [weak self] sessions in
                    guard let self, let id = routeID(self.route) else { return }
                    guard !sessions.contains(where: { $0.id == id }) else { return }
                    let remaining = self.sessionRoutes.filter { $0 != self.route }
                    if let fallback = remaining.first {
                        self.route = fallback
                    } else {
                        self.route = self.lastPlace
                    }
                }
                .store(in: &cancellables)
        }

        private var opensAutomatically: Bool {
            AppSettings.showsSessionOnConnect.value
        }

        // MARK: - Session actions

        /// - Parameter another: open one more terminal even when one is open,
        ///   without asking.
        func openTerminal(machine: RDMachine.ID, another: Bool = false) {
            // A UU Remote device may have sessions to resume: asked first, for
            // another tab (⌘T, +) too.
            guard let object = RayonStore.shared.machine(machine), object.isUURemoteDevice else {
                openTerminal(machine: machine, resuming: nil, another: another)
                return
            }
            let pick = {
                AppRouter.shared.present { dismiss in
                    UURemoteSessionPickerSheet(machine: object) { choice in
                        dismiss()
                        switch choice {
                        case .new: self.openTerminal(machine: machine, resuming: nil, another: true)
                        case let .resume(id): self.openTerminal(machine: machine, resuming: id, another: true)
                        case nil: break
                        }
                    }
                }
            }
            if !another, TerminalManager.shared.sessionContexts.contains(where: { $0.machine.id == machine }) {
                Indicator.confirm(
                    message: "\(object.name) already has a terminal open",
                    confirmTitle: "Open Another",
                    skippable: true
                ) { confirmed in
                    if confirmed { MainActor.assumeIsolated { pick() } }
                }
            } else {
                pick()
            }
        }

        private func openTerminal(machine: RDMachine.ID, resuming uuSession: UInt32?, another: Bool) {
            TerminalManager.shared.createSession(withMachineID: machine, force: another, resuming: uuSession) { [weak self] context in
                guard let self, self.opensAutomatically else { return }
                self.route = .terminal(context.id)
            }
        }

        func openTerminal(command: SSHCommandReader) {
            let context = TerminalManager.shared.createSession(withCommand: command)
            if opensAutomatically { route = .terminal(context.id) }
        }

        func openLocalTerminal(another: Bool = false) {
            if !another, let existing = TerminalManager.shared.sessionContexts.first(where: { $0.remoteType == .local && !$0.closed }) {
                route = .terminal(existing.id)
                return
            }
            let context = TerminalManager.shared.createLocalSession()
            if opensAutomatically { route = .terminal(context.id) }
        }

        func openMonitor(machine: RDMachine.ID) {
            do {
                let session = try MonitorCenter.shared.begin(for: machine)
                route = .monitor(session.id)
            } catch {
                Indicator.error(error.localizedDescription)
            }
        }

        /// Opens the server's remote desktop (VNC or UU Remote), reusing a live
        /// session. The session page reports "no remote desktop configured" on
        /// a server that has none, so callers do not have to check first.
        /// - Parameter viewOnly: watch the screen without sending input.
        func openDesktop(machine: RDMachine.ID, viewOnly: Bool = false) {
            guard let session = RemoteDesktopManager.shared.begin(for: machine) else { return }
            if viewOnly { session.viewOnly = true }
            route = .desktop(session.id)
        }

        func openFileTransfer(machine: RDMachine.ID) {
            let manager = FileTransferManager.shared
            if let existing = manager.transfers.first(where: { $0.machine.id == machine }) {
                route = .transfer(existing.id)
                return
            }
            manager.begin(for: machine)
            // Like Monitor, Files opens its page right away and connects in place.
            if let started = manager.transfers.last(where: { $0.machine.id == machine }) {
                route = .transfer(started.id)
            }
        }

        /// Shows the server's editor, connecting over SFTP if Files isn't open yet.
        @MainActor
        func openEditor(machine: RDMachine.ID) {
            let manager = FileTransferManager.shared
            if !manager.transfers.contains(where: { $0.machine.id == machine }) {
                manager.begin(for: machine)
            }
            if let context = manager.transfers.first(where: { $0.machine.id == machine }) {
                openEditor(context: context)
            }
        }

        /// Shows the editor of an SFTP session, with the file at `path` in front.
        @MainActor
        func openEditor(context: FileTransferContext, path: String? = nil) {
            let workspace = EditorCenter.shared.workspace(for: context)
            if let path { workspace.open(path: path) }
            route = .editor(context.id)
        }

        @MainActor
        func showInMenuBar(machine: RDMachine.ID) {
            MenubarTool.shared.createRuncat(for: machine)
        }

        /// Pick one or more servers, then open a terminal for each.
        @MainActor
        func openTerminals() {
            ServerPicker.present(title: "Open Terminals", confirmTitle: "Open") { machines in
                for machine in machines {
                    TerminalManager.shared.createSession(withMachineID: machine) { _ in }
                }
                if let first = TerminalManager.shared.sessionContexts.last(where: { machines.contains($0.machine.id) }),
                   self.opensAutomatically
                {
                    self.route = .terminal(first.id)
                }
            }
        }

        // MARK: - Sessions by server

        /// The remote desktop whose page is showing, if one is.
        var desktopInFront: RemoteDesktopSession? {
            guard case let .desktop(id) = route else { return nil }
            return RemoteDesktopManager.shared.session(withID: id)
        }

        /// The terminal whose page is showing, if one is.
        var terminalInFront: TerminalManager.Context? {
            guard case let .terminal(id) = route else { return nil }
            return TerminalManager.shared.sessionContexts.first { $0.id == id }
        }

        /// Who a session page belongs to.
        func owner(of route: Route) -> SessionOwner? {
            switch route {
            case let .terminal(id):
                guard let context = TerminalManager.shared.sessionContexts.first(where: { $0.id == id }) else { return nil }
                switch context.remoteType {
                case .machine: return .server(context.machine.id)
                case .command: return .command(context.id)
                case .local: return .local
                }
            case let .transfer(id), let .editor(id):
                return FileTransferManager.shared.transfers.first { $0.id == id }.map { .server($0.machine.id) }
            case let .monitor(id):
                return MonitorCenter.shared.session(withID: id).map { .server($0.machine.id) }
            case let .desktop(id):
                return RemoteDesktopManager.shared.session(withID: id).map { .server($0.machine.id) }
            default:
                return nil
            }
        }

        /// Every open session page, terminals first, then files, editors, monitors and desktops.
        var sessionRoutes: [Route] {
            TerminalManager.shared.sessionContexts.map { .terminal($0.id) }
                + FileTransferManager.shared.transfers.map { .transfer($0.id) }
                + EditorCenter.shared.workspaces.map { .editor($0.id) }
                + MonitorCenter.shared.sessions.map { .monitor($0.id) }
                + RemoteDesktopManager.shared.sessions.map { .desktop($0.id) }
        }

        /// Servers and Quick Connect terminals with something open, in the order
        /// their first session opened.
        var openOwners: [SessionOwner] {
            var seen = Set<SessionOwner>()
            return sessionRoutes.compactMap(owner(of:)).filter { seen.insert($0).inserted }
        }

        func routes(of owner: SessionOwner) -> [Route] {
            sessionRoutes.filter { self.owner(of: $0) == owner }
        }

        /// Shows a server's sessions: the tool it showed last, else the first open one.
        func show(_ owner: SessionOwner) {
            let open = routes(of: owner)
            if let last = lastRoute[owner], open.contains(last) {
                route = last
            } else if let first = open.first {
                route = first
            }
        }

        /// Closes every session of a server or Quick Connect terminal.
        @MainActor
        func closeAll(_ owner: SessionOwner) {
            for route in routes(of: owner) {
                switch route {
                case let .terminal(id):
                    if let context = TerminalManager.shared.sessionContexts.first(where: { $0.id == id }) {
                        TerminalManager.shared.closeSession(withContextID: context.id)
                    }
                case let .transfer(id):
                    FileTransferManager.shared.end(for: id)
                case let .editor(id):
                    EditorCenter.shared.end(id)
                case let .monitor(id):
                    MonitorCenter.shared.end(id)
                case let .desktop(id):
                    RemoteDesktopManager.shared.end(id)
                default:
                    break
                }
            }
        }

        /// ⌘T: another terminal to the server in front (from any of its pages),
        /// or to the same Quick Connect command; elsewhere, the picker.
        @MainActor
        func newTerminal() {
            guard !MainWindow.isShowingSheetOrModal else { return }
            switch owner(of: route) {
            case let .server(id):
                openTerminal(machine: id, another: true)
            case let .command(id):
                if let command = TerminalManager.shared.sessionContexts.first(where: { $0.id == id })?.command {
                    openTerminal(command: command)
                }
            case .local:
                openLocalTerminal(another: true)
            case nil:
                openTerminals()
            }
        }

        /// ⌘W: closes the session page in front, as a browser closes its tab.
        @MainActor
        func closeTabInFront() {
            guard !MainWindow.isShowingSheetOrModal else { return }
            switch route {
            case .terminal:
                if let terminal = terminalInFront { TerminalSessionActions.closeTab(terminal) }
            case let .transfer(id):
                if let context = FileTransferManager.shared.transfers.first(where: { $0.id == id }) {
                    FileTransferSessionActions.close(context)
                }
            case let .editor(id):
                if let workspace = EditorCenter.shared.workspaces.first(where: { $0.id == id }) {
                    EditorSessionActions.close(workspace)
                }
            case let .monitor(id):
                MonitorCenter.shared.end(id)
            case let .desktop(id):
                RemoteDesktopManager.shared.end(id)
            default:
                break
            }
        }

        /// Shows `content` as a sheet on the main window in front (the one
        /// a sheet or menu was used in); `dismiss` closes it. While that
        /// window shows a sheet, the request is refused: replacing the sheet
        /// would throw away what is typed in it.
        func present<Content: View>(@ViewBuilder _ content: @escaping (_ dismiss: @escaping () -> Void) -> Content) {
            let window = (NSApp.mainWindow ?? MainWindow.ordinaryWindows.first(where: \.isVisible))?.windowNumber
            sheets.removeAll { sheet in
                sheet.window.map { NSApp.window(withWindowNumber: $0) == nil } ?? false
            }
            if let shown = sheets.first(where: { $0.window == nil || $0.window == window }) {
                if let number = shown.window { NSApp.window(withWindowNumber: number)?.makeKeyAndOrderFront(nil) }
                NSSound.beep()
                return
            }
            sheets.append(WindowSheet(window: window) { AnyView(content($0)) })
        }

        /// The sheet `window` shows, if any.
        func sheet(in window: NSWindow?) -> WindowSheet? {
            sheets.first { sheet in
                guard let number = sheet.window else { return true }
                return number == window?.windowNumber
            }
        }

        func dismissSheet(_ id: WindowSheet.ID) {
            sheets.removeAll { $0.id == id }
        }

        /// Shows the Settings window, at `category` if one is given, else
        /// at the page it showed last.
        func openSettings(_ category: String? = nil) {
            if let category { settingsSelection = category }
            openWindow?(id: SettingsWindow.id)
        }
    }

    struct WindowSheet: Identifiable {
        let id = UUID()
        /// The number of the window it shows in; nil, with no window open,
        /// shows it in the first one that opens.
        let window: Int?
        let content: (_ dismiss: @escaping () -> Void) -> AnyView
    }

    /// What owns a group of session pages: a saved server, or one Quick Connect
    /// terminal (which has no saved server to group under).
    enum SessionOwner: Hashable {
        case server(RDMachine.ID)
        case command(UUID)
        case local
    }

    extension Route {
        var isSession: Bool {
            switch self {
            case .terminal, .monitor, .transfer, .editor, .desktop: return true
            default: return false
            }
        }
    }

    enum SettingsCategory {
        static let general = "general"
        static let about = "about"
    }

#endif
