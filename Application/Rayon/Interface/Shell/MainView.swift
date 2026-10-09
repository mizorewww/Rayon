//
//  MainView.swift
//  Rayon (macOS)
//
//  The main window: a native sidebar (Liquid Glass on macOS 26) over a translucent
//  window, and the content column.
//

import MachineStatusView
import RayonModule
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
            // Pages cross-fade with a slight rise, so the eye follows the change
            // of place instead of seeing the content column jump.
            ZStack {
                RXWindowBackground()
                    .ignoresSafeArea()
                // Places (Home, Servers, Settings…) cross-fade with a slight rise,
                // so the eye follows the change of place.
                if !router.route.isSession {
                    content
                        .id(router.route)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity
                        ))
                }
                SessionPages(route: router.route)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: router.route.isSession ? nil : router.route)
            // Set here, outside the page transition, so the toolbar never falls
            // back to its opaque background while one page fades into another.
            .toolbarBackground(.hidden, for: .windowToolbar)
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
        }
        .sheet(isPresented: $openLicenseAgreement) {
            AgreementSheet()
        }
        .onAppear {
            onMainThread(delay: 0.5) {
                if !store.licenseAgreed { openLicenseAgreement = true }
            }
        }
    }

    @ViewBuilder var content: some View {
        switch router.route {
        case .home:
            HomeView()
        case .servers:
            ServersView()
        case .identities:
            IdentitiesView()
        case .snippets:
            SnippetsView()
        case .portForward:
            PortForwardView()
        case .settings:
            SettingsView()
        case .terminal, .monitor, .transfer:
            EmptyView()
        }
    }
}

/// Every open terminal, file browser and monitor stays mounted; the route only
/// decides which one is visible. Switching between a server's Terminal, Files
/// and Monitor (or between servers) is then a change of visibility, with no
/// page or terminal surface rebuilt and scroll positions kept.
private struct SessionPages: View {
    let route: Route
    @ObservedObject var terminals = TerminalManager.shared
    @ObservedObject var transfers = FileTransferManager.shared
    @ObservedObject var monitors = MonitorCenter.shared

    var body: some View {
        ZStack {
            ForEach(terminals.sessionContexts) { context in
                TerminalPage(context: context)
                    .sessionPage(active: route == .terminal(context.id))
            }
            ForEach(transfers.transfers) { context in
                FileTransferPage(context: context)
                    .sessionPage(active: route == .transfer(context.id))
            }
            ForEach(monitors.sessions) { session in
                MonitorPage(session: session)
                    .sessionPage(active: route == .monitor(session.id))
            }
        }
    }
}

private extension View {
    func sessionPage(active: Bool) -> some View {
        opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(active ? 1 : 0)
            .environment(\.isActivePage, active)
            // No fade between a server's tools: two different layouts mixing for
            // a moment reads as lag, while an instant change feels immediate.
    }
}

/// The window toolbar holds page controls only; the page title is in the content.
private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
    }
}
