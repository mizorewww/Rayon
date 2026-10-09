//
//  TerminalPage.swift
//  Rayon (macOS)
//
//  A session inside the main window: session tabs; the Terminal · Files · Monitor
//  switcher; text size, Reconnect, Close.
//  Status bar: state, user@host:port, live CPU / memory while monitored, font size.
//

import MachineStatusView
import RayonModule
import RayonTerminal
import SwiftUI

struct TerminalPage: View {
    @ObservedObject var context: TerminalManager.Context
    @ObservedObject var terminals = TerminalManager.shared
    @EnvironmentObject var store: RayonStore

    @State private var interfaceToken = UUID()
    @Environment(\.isActivePage) private var isActive

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if context.closed {
                    disconnectedBanner
                }
                surface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // No backdrop of our own: Ghostty paints its background with
            // `background-opacity`, so a translucent terminal shows the window
            // material underneath instead of an opaque fill.
            .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
            .padding(.horizontal, RX.Space.s6)
            TerminalStatusBar(context: context)
                .padding(.horizontal, RX.Space.s6)
        }
        .padding(.top, RX.Space.s3)
        .pageChrome()
        .pageToolbar {
            SessionTabs(selection: context.id)
        } trailing: {
            Group {
                ControlGroup {
                    Button {
                        store.terminalFontSize -= 1
                    } label: {
                        Label("Smaller Text", systemImage: "textformat.size.smaller")
                    }
                    .disabled(store.terminalFontSize <= 4)
                    .keyboardShortcut("-", modifiers: .command)
                    Button {
                        store.terminalFontSize += 1
                    } label: {
                        Label("Larger Text", systemImage: "textformat.size.larger")
                    }
                    .disabled(store.terminalFontSize >= 30)
                    .keyboardShortcut("+", modifiers: .command)
                }
                .help("Text Size")
                if context.closed {
                    ToolbarAction("Reconnect", systemImage: "arrow.clockwise", primary: true) {
                        context.reconnect()
                    }
                }
                ToolbarAction("Close Session", systemImage: "xmark") {
                    TerminalSessionActions.close(context)
                }
            }
        }
        .serverToolSwitcher(
            machine: context.remoteType == .machine && context.machine.isNotPlaceholder() ? context.machine.id : nil,
            current: .terminal
        )
        .onAppear {
            context.interfaceToken = interfaceToken
            context.termInterface.setActive(isActive)
        }
        .onChange(of: isActive) { active in
            context.termInterface.setActive(active)
        }
    }

    @ViewBuilder var surface: some View {
        if context.interfaceToken == interfaceToken {
            context.termInterface
                .onChange(of: store.terminalFontSize) { newValue in
                    context.termInterface.setTerminalFontSize(with: newValue)
                }
                .onAppear {
                    context.termInterface.setTerminalFontSize(with: store.terminalFontSize, preferConfigured: true)
                }
        } else {
            EmptyStateView(
                "Terminal moved to another window",
                systemImage: "macwindow",
                actionTitle: "Bring Back Here"
            ) {
                context.interfaceToken = interfaceToken
            }
            .environment(\.colorScheme, .dark)
            .background(Color.rxTerminalBackground)
        }
    }

    var disconnectedBanner: some View {
        HStack(spacing: RX.Space.s2) {
            Text("Connection closed")
                .foregroundStyle(.rxTerminalForeground)
            Spacer()
        }
        .font(.rxBody)
        .padding(.horizontal, RX.Space.s3)
        .frame(height: 36)
        .background(Color.black.opacity(0.35))
    }
}

/// Tabs for open terminal sessions. Selected tab: `surface` with `shadow-card`.
struct SessionTabs: View {
    let selection: TerminalManager.Context.ID
    @ObservedObject var terminals = TerminalManager.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RX.Space.s1) {
                ForEach(terminals.sessionContexts) { context in
                    SessionTab(context: context, selected: context.id == selection)
                }
                Button {
                    AppRouter.shared.openTerminals()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.rxInkSecondary)
                .help("Open Terminals…")
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SessionTab: View {
    @ObservedObject var context: TerminalManager.Context
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(context.displayName)
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.rxInk : Color.rxInkSecondary)
                .lineLimit(1)
                .frame(maxWidth: 160)
            Button {
                TerminalSessionActions.close(context)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.rxInkSecondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(selected || hovered ? 1 : 0)
            .accessibilityLabel("Close \(context.navigationTitle)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: RX.controlHeight)
        .background {
            if selected {
                Capsule().fill(Color.primary.opacity(0.1))
            } else if hovered {
                Capsule().fill(Color.primary.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { AppRouter.shared.route = .terminal(context.id) }
        .onHover { hovered = $0 }
        .contextMenu {
            if context.closed { Button("Reconnect") { context.reconnect() } }
            Button("Close Session") { TerminalSessionActions.close(context) }
        }
    }
}

/// State, user@host:port, live CPU and memory while a monitor is open, font size.
private struct TerminalStatusBar: View {
    @ObservedObject var context: TerminalManager.Context
    @ObservedObject var monitors = MonitorCenter.shared
    @EnvironmentObject var store: RayonStore

    var body: some View {
        HStack(spacing: RX.Space.s4) {
            RedactableText(endpoint, redacted: store.machineRedacted != .none)
                .font(.rxCode)
            if !context.navigationSubtitle.isEmpty, context.navigationSubtitle != context.navigationTitle {
                Text(context.navigationSubtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: RX.Space.s2)
            if let session = monitors.session(for: context.machine.id) {
                LiveFigures(session: session)
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.rxInkSecondary)
        .padding(.horizontal, RX.Space.s1)
        .frame(height: 32)
    }

    var endpoint: String {
        if let command = context.command { return command.command }
        return context.machine.getCommand(insertLeadingSSH: false)
    }

    private struct LiveFigures: View {
        @ObservedObject var session: MonitorSession
        var body: some View {
            if session.status.hasData {
                Text("CPU \(RXFormat.percent(Double(session.status.processor.summary.sumUsed)))%")
                Text("Mem \(RXFormat.percent(session.status.memoryUsedPercent))%")
                Text("↓ \(RXFormat.rateString(Double(session.status.totalReceivePerSecond))) ↑ \(RXFormat.rateString(Double(session.status.totalTransmitPerSecond)))")
            }
        }
    }
}

enum TerminalSessionActions {
    static func close(_ context: TerminalManager.Context) {
        let manager = TerminalManager.shared
        if manager.sessionAlive(forContext: context.id) {
            UIBridge.requiresConfirmation(
                message: "Close the session on \(context.displayName)?",
                confirmTitle: "Close Session",
                destructive: true
            ) { confirmed in
                if confirmed { manager.closeSession(withContextID: context.id) }
            }
        } else {
            manager.closeSession(withContextID: context.id)
        }
    }
}

extension TerminalManager.Context {
    /// The server's name, or `user@host` for a Quick Connect session.
    var displayName: String {
        if remoteType == .machine { return machine.name }
        if let command { return "\(command.username)@\(command.remoteAddress)" }
        return navigationTitle
    }

    /// Reconnects with the details from when this session started.
    func reconnect() {
        guard closed else { return }
        DispatchQueue.global().async {
            self.putInformation("[i] Reconnecting with the details from when this session started.")
            self.putInformation("    If the server was edited, open a new terminal instead.")
            self.processBootstrap()
        }
    }
}
