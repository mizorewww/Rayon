//
//  MonitorPage.swift
//  Rayon (macOS)
//
//  A server's monitor (a session in the sidebar): back to Servers, refresh state,
//  Show in Menu Bar, Files, Terminal; the page header, then the card grid.
//

import MachineStatusView
import RayonModule
import SwiftUI

struct MonitorPage: View {
    @ObservedObject var session: MonitorSession
    @EnvironmentObject var store: RayonStore

    var body: some View {
        PageScaffold {
            BackButton(title: "Servers") { AppRouter.shared.route = .servers }
        } trailing: {
            ToolbarAction("Show in Menu Bar", systemImage: "menubar.rectangle") {
                AppRouter.shared.showInMenuBar(machine: session.machine.id)
            }
            ToolbarAction("Open File Transfer", systemImage: "arrow.up.arrow.down") {
                AppRouter.shared.openFileTransfer(machine: session.machine.id)
            }
            ToolbarAction("Close Monitor", systemImage: "xmark") {
                MonitorCenter.shared.end(session.id)
            }
            ToolbarAction("Terminal", systemImage: "terminal", primary: true) {
                AppRouter.shared.openTerminal(machine: session.machine.id)
            }
        } header: {
            VStack(alignment: .leading, spacing: RX.Space.s5) {
                PageTitle(store.machineRedacted == .all ? "Server" : session.machine.name)
                MonitorFacts(session: session, redactAddress: store.machineRedacted != .none)
            }
        } content: {
            if session.phase == .connected, session.status.hasData {
                MonitorDashboard(session: session)
            } else {
                MonitorPlaceholder(session: session)
            }
        }
    }
}
