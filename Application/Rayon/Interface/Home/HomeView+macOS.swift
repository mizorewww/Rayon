//
//  HomeView+macOS.swift
//  Rayon
//
//  Start page, laid out as the first Rayon had it: the app icon, Quick Connect
//  (the typed command read back as user, host and port) and the version, over
//  a soft glow with drifting dots. The server tiles are on Dashboard.
//

#if os(macOS)
    import MachineStatusView
    import RayonModule
    import SwiftUI

    struct HomeView: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.animatesHome) private var animatesHome

        var body: some View {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: RX.Space.s6)
                        QuickConnectHero()
                        TelemetryNoticeCard()
                            .padding(.top, RX.Space.s6)
                        Spacer(minLength: RX.Space.s6)
                        Text(RXAppVersion.text)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.rxInkTertiary)
                            .textSelection(.enabled)
                    }
                    .padding(RX.Space.s6)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
            .background {
                if animatesHome {
                    RXStarfield().ignoresSafeArea()
                }
            }
            .pageChrome()
        }
    }

    // MARK: - Quick Connect

    /// The fast way in: type `user@host` or an ssh command and press Return.
    /// Focused on open. What was typed is read back as separate User, Host and
    /// Port tokens, so it is clear what Return will connect to before pressing
    /// it. A saved server's name, alone or after "ssh ", connects to that server,
    /// the way `ssh myserver` reads a Host from ~/.ssh/config.
    struct QuickConnectHero: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.remembersRecentCommands) private var remembersCommands
        @AppSetting(AppSettings.remembersRecent) private var remembersRecent
        @State private var command = ""
        @State private var suggestion: String?
        @FocusState private var focused: Bool

        var parsed: SSHCommandReader? {
            SSHCommandReader(quickConnect: command)
        }

        /// The saved server the input names, when it is not a `user@host`.
        var savedServer: RDMachine? {
            parsed == nil ? store.machine(matchingQuickConnect: command) : nil
        }

        var body: some View {
            let parsed = parsed
            let savedServer = savedServer
            let canConnect = parsed != nil || savedServer != nil
            VStack(spacing: RX.Space.s3) {
                RXAppIcon(size: 128)
                    .padding(.bottom, RX.Space.s1)

                Text("Quick Connect")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.rxInk)

                VStack(alignment: .leading, spacing: RX.Space.s2) {
                    HStack(spacing: RX.Space.s3) {
                        Image(systemName: "terminal")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.rxInkSecondary)
                            .accessibilityHidden(true)
                        TextField("user@host:22", text: $command)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .regular, design: .monospaced))
                            .disableAutocorrection(true)
                            .focused($focused)
                            .onSubmit(connect)
                            .onChange(of: command) { newValue in
                                if newValue.hasPrefix("ssh ssh ") { command.removeFirst("ssh ".count) }
                                refreshSuggestion()
                            }
                            .accessibilityLabel("Quick Connect")
                        Button(action: connect) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(canConnect ? Color.white : Color.rxInkTertiary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(canConnect ? Color.rxAccent : Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canConnect)
                        .scaleEffect(canConnect ? 1 : 0.94)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canConnect)
                        .help("Connect (↩)")
                        .accessibilityLabel("Connect")
                    }
                    .padding(.leading, RX.Space.s5)
                    .padding(.trailing, RX.Space.s2)
                    .frame(height: 64)
                    .background(
                        Capsule()
                            .fill(Color.rxSurface)
                            .overlay(Capsule().strokeBorder(focused ? Color.clear : Color.rxHairline, lineWidth: 0.5))
                            .overlay(Capsule().strokeBorder(Color.rxAccent.opacity(focused ? 0.5 : 0), lineWidth: 1.5))
                            .shadow(color: .black.opacity(focused ? 0.12 : 0.06), radius: focused ? 14 : 10, y: 4)
                    )
                    .animation(.easeOut(duration: 0.2), value: focused)

                    if let suggestion {
                        Button {
                            command = suggestion
                            connect()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Did you mean “\(suggestion)”?")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                KeyHint("⌘↩")
                            }
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.rxInkSecondary)
                            .padding(.leading, 8)
                            .padding(.trailing, 4)
                            .frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: RX.Radius.md, style: .continuous).fill(Color.primary.opacity(0.06)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Connect with this recent command")
                        .transition(.offset(y: -6).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: 640)

                Group {
                    if let parsed {
                        ParsedCommand(command: parsed)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    } else if let savedServer {
                        SavedServerTarget(machine: savedServer)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    } else if !"ssh ".hasPrefix(command.lowercased()) {
                        Text("Type user@host, user@host:port, a saved server's name or a full ssh command.")
                            .font(.rxHelp)
                            .foregroundStyle(.rxInkSecondary)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: parsed)
                .animation(.easeOut(duration: 0.2), value: savedServer?.id)

                Toggle("Record Command", isOn: $remembersCommands)
                    .toggleStyle(.checkbox)
                    .font(.system(.body, design: .rounded))
                    .disabled(!remembersRecent)
                    .help(remembersRecent
                        ? "Keep the commands typed here under Recent"
                        : "Turn on “Remember recent servers” in Settings to keep commands")

                if store.identitiesForAutoAuth.isEmpty {
                    HStack(spacing: RX.Space.s2) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Quick Connect signs in with identities set to “Authenticate automatically”. You have none yet.")
                        Button("Open Identities") { AppRouter.shared.route = .identities }
                            .rxLinkButton()
                    }
                    .font(.rxHelp)
                    .foregroundStyle(.rxWarning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                }

                Button {
                    AppRouter.shared.openLocalTerminal()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 12))
                        Text("Open Local Terminal")
                            .font(.system(size: 12, weight: .medium))
                        KeyHint("⌥⌘T")
                    }
                    .foregroundStyle(.rxInk)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open a local shell on this Mac (⌥⌘T)")
                .padding(.top, RX.Space.s2)

                if remembersRecent, store.recentRecord.contains(where: \.isCommand) {
                    VStack(spacing: RX.Space.s2) {
                        CapsLabel("Recent")
                        RXFlowLayout(spacing: RX.Space.s2, alignment: .center) {
                            // Saved servers are on Dashboard; Recent keeps the
                            // Quick Connect commands, which have nowhere else.
                            ForEach(store.recentRecord.filter(\.isCommand)) { record in
                                RecentChip(record: record)
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.top, RX.Space.s2)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: suggestion)
            .onAppear {
                onMainThread(delay: 0.2) { focused = true }
            }
        }

        func connect() {
            if let parsed {
                AppRouter.shared.openTerminal(command: parsed)
            } else if let savedServer {
                ServerTool.terminal.show(savedServer.id)
            } else {
                return
            }
            command = ""
        }

        func refreshSuggestion() {
            suggestion = SSHCommandReader.suggestion(
                for: command,
                in: store.recentRecord.lazy.map(\.equivalentSSHCommand)
            )
        }
    }

    /// The parsed command as distinct tokens: who, where, which port.
    private struct ParsedCommand: View {
        let command: SSHCommandReader

        var body: some View {
            HStack(spacing: RX.Space.s2) {
                QuickConnectToken(title: "User", value: command.username, systemImage: "person", tint: .rxAccent)
                QuickConnectToken(title: "Host", value: command.remoteAddress, systemImage: "network", tint: .rxSeries2)
                QuickConnectToken(title: "Port", value: command.remotePort, systemImage: "number", tint: .rxInkSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The saved server a typed alias names, read back like a parsed command.
    private struct SavedServerTarget: View {
        @EnvironmentObject var store: RayonStore
        let machine: RDMachine

        var body: some View {
            HStack(spacing: RX.Space.s2) {
                QuickConnectToken(title: "Server", value: machine.name, systemImage: "server.rack", tint: .rxAccent)
                let username = machine.sshLoginUsername(identity: store.associatedIdentity(for: machine))
                if !username.isEmpty {
                    QuickConnectToken(title: "User", value: username, systemImage: "person", tint: .rxAccent)
                }
                QuickConnectToken(title: "Host", value: machine.remoteAddress, systemImage: "network", tint: .rxSeries2)
                QuickConnectToken(title: "Port", value: machine.remotePort, systemImage: "number", tint: .rxInkSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// One part of what Return connects to: a caps title and its value.
    private struct QuickConnectToken: View {
        let title: String
        let value: String
        let systemImage: String
        let tint: Color

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.rxCaption)
                    .tracking(rxCapsTracking)
                    .foregroundStyle(.rxInkSecondary)
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
        }
    }

    /// A recent server or command; one click connects.
    struct RecentChip: View {
        let record: RayonStore.RecentConnection
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @State private var hovered = false

        var title: String {
            switch record {
            case let .command(command):
                // Only the leading "ssh " is decoration; one inside the
                // arguments is part of the command.
                var title = command.command
                if title.hasPrefix("ssh ") { title.removeFirst("ssh ".count) }
                return title
            case let .machine(id):
                return store.machine(id)?.name ?? "Deleted server"
            }
        }

        var body: some View {
            Button(action: connect) {
                HStack(spacing: 6) {
                    Image(systemName: isCommand ? "terminal" : "server.rack")
                        .font(.system(size: 11))
                    RedactableText(title, redacted: !isCommand && redaction == .all)
                        .font(.system(size: 12, design: isCommand ? .monospaced : .default))
                        .lineLimit(1)
                }
                .foregroundStyle(.rxInk)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Color.primary.opacity(hovered ? 0.12 : 0.07)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .contextMenu {
                Button("Copy Command") { Pasteboard.copy(record.equivalentSSHCommand) }
                Divider()
                Button("Remove from Recent", role: .destructive) {
                    store.recentRecord.removeAll { $0.id == record.id }
                }
            }
        }

        var isCommand: Bool {
            if case .command = record { return true }
            return false
        }

        func connect() {
            switch record {
            case let .command(command): AppRouter.shared.openTerminal(command: command)
            case let .machine(machine): AppRouter.shared.openTerminal(machine: machine)
            }
        }
    }

    extension RayonStore.RecentConnection {
        /// A Quick Connect command rather than a saved server.
        var isCommand: Bool {
            if case .command = self { return true }
            return false
        }
    }

#endif
