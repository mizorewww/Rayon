//
//  MainView+macOS.swift
//  Rayon
//

#if os(macOS)
    import RayonModule
    import MachineStatusView
    import SwiftUI

    struct MainView: View {
        @ObservedObject var router = AppRouter.shared

        @State private var openLicenseAgreement = false

        var body: some View {
            NavigationSplitView(columnVisibility: $router.columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: RX.sidebarWidth, max: 280)
            } detail: {
                ZStack {
                    RXWindowBackground()
                        .ignoresSafeArea()
                    // Only the page in front is mounted. What outlives it — a
                    // terminal's surface, a desktop's connection, a folder's
                    // history, the editor's files — is in the session models.
                    // Pages swap in one frame, as a split view's detail does:
                    // a fade-in left the window empty for a few frames, since
                    // the page going away (and its toolbar) left at once.
                    if router.route.isSession {
                        SessionPage(route: router.route)
                    } else {
                        place
                            .id(router.route)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rxClearToolbar()
                .pageToolbarItems()
            }
            .frame(minWidth: 940, minHeight: 600)
            .modifier(HiddenWindowTitle())
            .routerSheets()
            .sheet(isPresented: $openLicenseAgreement) {
                AgreementSheet()
            }
            .onAppear {
                if !RayonStore.shared.licenseAgreed { openLicenseAgreement = true }
            }
        }

        @ViewBuilder var place: some View {
            switch router.route {
            case .home:
                HomeView()
            case .dashboard:
                DashboardView()
            case .servers:
                ServersView()
            case .identities:
                IdentitiesView()
            case .snippets:
                SnippetsView()
            case .portForward:
                PortForwardView()
            case .desktops:
                RemoteDesktopsView()
            case .terminal, .monitor, .transfer, .editor, .desktop:
                EmptyView()
            }
        }
    }

    /// The session page the route shows. Terminal tabs share one page, which
    /// keeps its find bar and snippet drawer as the tabs switch; every other
    /// session gets a page of its own.
    private struct SessionPage: View {
        let route: Route
        @ObservedObject var terminals = TerminalManager.shared
        @ObservedObject var transfers = FileTransferManager.shared
        @ObservedObject var editors = EditorCenter.shared
        @ObservedObject var monitors = MonitorCenter.shared
        @ObservedObject var desktops = RemoteDesktopManager.shared

        var body: some View {
            switch route {
            case let .terminal(id):
                if let context = terminals.sessionContexts.first(where: { $0.id == id }) {
                    TerminalPage(context: context)
                }
            case let .transfer(id):
                if let context = transfers.transfers.first(where: { $0.id == id }) {
                    FileTransferPage(context: context).id(id)
                }
            case let .editor(id):
                if let workspace = editors.workspaces.first(where: { $0.id == id }) {
                    EditorPage(workspace: workspace).id(id)
                }
            case let .monitor(id):
                if let session = monitors.sessions.first(where: { $0.id == id }) {
                    MonitorPage(session: session).id(id)
                }
            case let .desktop(id):
                if let session = desktops.sessions.first(where: { $0.id == id }) {
                    RemoteDesktopPage(session: session).id(id)
                }
            default:
                EmptyView()
            }
        }
    }

    private struct HiddenWindowTitle: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 15.0, *) {
                content
                    .navigationTitle("Rayon")
                    .toolbar(removing: .title)
            } else {
                content.navigationTitle("Rayon")
            }
        }
    }

    extension View {
        /// Shows the router's sheets that are for this view's window: the
        /// main windows and Settings each show those asked for in them.
        func routerSheets() -> some View {
            modifier(RouterSheets())
        }
    }

    private struct RouterSheets: ViewModifier {
        @ObservedObject private var router = AppRouter.shared
        @StateObject private var anchor = WindowAnchor()

        func body(content: Content) -> some View {
            content
                .background(WindowReader(anchor: anchor))
                .sheet(item: Binding(
                    get: { router.sheet(in: anchor.window) },
                    set: { if $0 == nil, let shown = router.sheet(in: anchor.window) { router.dismissSheet(shown.id) } }
                )) { sheet in
                    sheet.content { router.dismissSheet(sheet.id) }
                        .environmentObject(RayonStore.shared)
                }
                // A sheet asked for with no window open goes to the first
                // window shown, or the first on screen once it is asked for.
                .onChange(of: anchor.window, initial: true) { router.claimSheet(for: anchor.window) }
                .onChange(of: router.sheets.contains { $0.window == nil }) { router.claimSheet(for: anchor.window) }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                    if note.object as? NSWindow === anchor.window { router.claimSheet(for: anchor.window) }
                }
        }
    }

    /// The window a view is in, published after AppKit has inserted the view.
    @MainActor
    private final class WindowAnchor: ObservableObject {
        // Weak: the window holds this view, and so this anchor.
        weak var window: NSWindow? {
            willSet { objectWillChange.send() }
        }
    }

    private struct WindowReader: NSViewRepresentable {
        let anchor: WindowAnchor

        func makeNSView(context _: Context) -> Probe {
            Probe(anchor: anchor)
        }

        func updateNSView(_: Probe, context _: Context) {}

        final class Probe: NSView {
            let anchor: WindowAnchor

            init(anchor: WindowAnchor) {
                self.anchor = anchor
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                // Not during the insertion, which can run inside a SwiftUI update.
                Task { @MainActor [anchor, window] in anchor.window = window }
            }
        }
    }
#endif
