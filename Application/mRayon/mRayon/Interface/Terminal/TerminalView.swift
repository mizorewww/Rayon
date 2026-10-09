//
//  TerminalView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//
//  A Ghostty terminal for one session. The key bar above the software keyboard
//  (esc, tab, sticky ctrl/alt/cmd, arrows, symbols, paste) comes from Ghostty's
//  UITerminalView; the toolbar holds the session actions.
//

import RayonModule
import RayonTerminal
import SwiftUI

struct TerminalView: View {
    @StateObject var context: TerminalContext

    @State var interfaceToken = UUID()

    @State var terminalSize: CGSize = TerminalContext.defaultTerminalSize

    @StateObject var store = RayonStore.shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                GeometryReader { r in
                    context.termInterface
                        .onChange(of: r.size) { _ in
                            guard context.interfaceToken == interfaceToken else {
                                debugPrint("interface token mismatch")
                                return
                            }
                            updateTerminalSize()
                        }
                        .onAppear {
                            context.termInterface.setTerminalFontSize(with: store.terminalFontSize, preferConfigured: true)
                        }
                        .onChange(of: store.terminalFontSize) { newValue in
                            context.termInterface.setTerminalFontSize(with: newValue)
                        }
                        .padding(r.size.width > 600 ? 8 : 2)
                }
            } else {
                EmptyStateView(
                    "Terminal moved to another window",
                    systemImage: "macwindow",
                    message: "This session is open in another window."
                )
            }
        }
        // No opaque fill behind the surface: Ghostty paints its own background,
        // so a translucent terminal shows the page backdrop.
        .background(RXBackdrop().ignoresSafeArea())
        .onAppear {
            debugPrint("set interface token \(interfaceToken)")
            context.interfaceToken = interfaceToken
        }
        .navigationTitle(context.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if context.closed {
                    Button {
                        DispatchQueue.global().async {
                            context.putInformation("[i] Reconnecting with the details from when this session started.")
                            context.putInformation("    If the server was edited, open a new terminal instead.")
                            context.processBootstrap()
                        }
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                }
                Button(role: .destructive) {
                    closeSession()
                } label: {
                    Label("Close Session", systemImage: "xmark.circle")
                }
            }
        }
    }

    func closeSession() {
        if context.closed {
            dismiss()
            TerminalManager.shared.end(for: context.id)
        } else {
            UIBridge.requiresConfirmation(
                message: "Close this session?",
                informative: "Anything running in it is stopped.",
                confirmTitle: "Close Session"
            ) { yes in
                if yes { context.processShutdown() }
            }
        }
    }

    func updateTerminalSize() {
        let core = context.termInterface
        let origSize = terminalSize
        DispatchQueue.global().async {
            let newSize = core.requestTerminalSize()
            guard newSize.width > 5, newSize.height > 5 else {
                debugPrint("ignoring malformed terminal size: \(newSize)")
                return
            }
            if newSize != origSize {
                onMainThread {
                    guard context.interfaceToken == interfaceToken else {
                        debugPrint("interface token mismatch")
                        return
                    }
                    debugPrint("new terminal size: \(newSize)")
                    terminalSize = newSize
                    context.shell.explicitRequestStatusPickup()
                }
            }
        }
    }
}
