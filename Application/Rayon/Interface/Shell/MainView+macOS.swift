//
//  MainView+macOS.swift
//  Rayon
//

#if os(macOS)
    import RayonModule
    import MachineStatusView
    import SwiftUI

    struct MainView: View {
        @EnvironmentObject var store: RayonStore
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
                    if router.route.isSession {
                        SessionPage(route: router.route)
                    } else {
                        place
                            .id(router.route)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 6)),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.2), value: router.route.isSession ? nil : router.route)
                .rxClearToolbar()
            }
            .frame(minWidth: 940, minHeight: 600)
            .modifier(HiddenWindowTitle())
            .overlay {
                if store.globalProgressInPresent {
                    ProgressHUD()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: store.globalProgressInPresent)
            .sheet(isPresented: $router.presentNewServer) {
                ServerEditorSheet(machine: nil)
                    .environmentObject(RayonStore.shared)
            }
            .sheet(isPresented: $openLicenseAgreement) {
                AgreementSheet()
            }
            .onAppear {
                if !store.licenseAgreed { openLicenseAgreement = true }
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
            case .settings:
                SettingsView()
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

#endif
