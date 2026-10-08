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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case let .terminal(id):
            if let context = TerminalManager.shared.sessionContexts.first(where: { $0.id == id }) {
                TerminalPage(context: context)
                    .id(id)
            } else {
                HomeView()
            }
        case let .monitor(id):
            if let session = MonitorCenter.shared.session(withID: id) {
                MonitorPage(session: session)
                    .id(id)
            } else {
                ServersView()
            }
        case let .transfer(id):
            if let context = FileTransferManager.shared.transfers.first(where: { $0.id == id }) {
                FileTransferPage(context: context)
                    .id(id)
            } else {
                HomeView()
            }
        }
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
