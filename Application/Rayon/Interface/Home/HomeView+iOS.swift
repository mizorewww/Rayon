//
//  HomeView+iOS.swift
//  Rayon
//
//  Home, laid out as the first Rayon had it: the app icon, Quick Connect,
//  recent connections and the version, over a slowly drifting colour wash.
//  The server tiles are on Dashboard.
//

#if os(iOS)
    import MachineStatusView
    import RayonModule
    import SwiftUI

    struct HomeView: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.animatesHome) private var animatesHome
        @AppSetting(AppSettings.remembersRecent) private var remembersRecent

        var body: some View {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: RX.Space.s4)
                        QuickConnectCard()
                        if remembersRecent, !store.recentRecord.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: RX.Space.s2) {
                                    ForEach(store.recentRecord) { record in
                                        RecentRow(record: record)
                                    }
                                }
                                .padding(.horizontal, RX.Space.s4)
                            }
                            .padding(.horizontal, -RX.Space.s4)
                            .padding(.top, RX.Space.s5)
                        }
                        TelemetryNoticeCard()
                            .padding(.top, RX.Space.s5)
                        Spacer(minLength: RX.Space.s6)
                        Text(RXAppVersion.text)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.rxInkTertiary)
                    }
                    .padding(RX.Space.s4)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
            .background {
                ZStack {
                    RXBackdrop()
                    if animatesHome {
                        HomeBackdrop()
                    }
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Type `user@host:port` or a full ssh command and connect. Uses identities that authenticate automatically.
    /// A saved server's name, alone or after "ssh ", connects to that server.
    struct QuickConnectCard: View {
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.remembersRecentCommands) private var remembersCommands
        @AppSetting(AppSettings.remembersRecent) private var remembersRecent
        @State private var command = ""
        @State private var suggestion: String?
        /// Data pasted for the hidden importer, waiting for its key.
        @State private var importData: Data?

        var parsed: SSHCommandReader? {
            SSHCommandReader(quickConnect: command)
        }

        /// The saved server the input names, when it is not a `user@host`.
        var savedServer: RDMachine? {
            parsed == nil ? store.machine(matchingQuickConnect: command) : nil
        }

        var body: some View {
            let savedServer = savedServer
            let canConnect = parsed != nil || savedServer != nil
            VStack(spacing: RX.Space.s3) {
                RXAppIcon(size: 112)
                    .padding(.bottom, RX.Space.s1)
                Text("Quick Connect")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.rxInk)
                VStack(alignment: .leading, spacing: RX.Space.s2) {
                    HStack(spacing: RX.Space.s2) {
                        Image(systemName: "terminal")
                            .font(.system(size: 18))
                            .foregroundStyle(.rxInkSecondary)
                        TextField("ssh user@host -p 22", text: $command)
                            .font(.system(size: 19, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit(connect)
                            .onChange(of: command) { newValue in
                                if newValue.hasPrefix("ssh ssh ") { command.removeFirst("ssh ".count) }
                                refreshSuggestion()
                            }
                        Button(action: connect) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.rxOnAccent)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.rxAccent))
                        }
                        .disabled(!canConnect)
                        .opacity(canConnect ? 1 : 0.35)
                        .simultaneousGesture(LongPressGesture().onEnded { _ in importFromPasteboard() })
                        .accessibilityLabel("Connect")
                    }
                    .padding(.leading, RX.Space.s4)
                    .padding(.trailing, 6)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .fill(.thickMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    )
                    if let suggestion {
                        Button {
                            command = suggestion
                            connect()
                        } label: {
                            Text("Did you mean “\(suggestion)”?")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.rxInkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
                        }
                        .buttonStyle(.plain)
                        .transition(.offset(y: -6).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: 480)
                if let savedServer {
                    Label("\(savedServer.name) · \(savedServerTarget(savedServer))", systemImage: "server.rack")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                        .accessibilityLabel("Connects to the saved server \(savedServer.name)")
                }
                Button {
                    remembersCommands.toggle()
                } label: {
                    Label("Record Command", systemImage: remembersCommands ? "checkmark.square.fill" : "square")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(remembersCommands ? Color.rxAccent : Color.rxInkSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!remembersRecent)
                .opacity(remembersRecent ? 1 : 0.5)
                .accessibilityValue(remembersCommands ? "On" : "Off")
                // Said once a command is typed: before, it read as an error
                // on a page with nothing wrong yet.
                if store.identitiesForAutoAuth.isEmpty, !command.isEmpty {
                    Text("Quick Connect needs an identity that authenticates automatically.")
                        .font(.footnote)
                        .foregroundStyle(.rxWarning)
                        .multilineTextAlignment(.center)
                }
            }
            .animation(.easeOut(duration: 0.2), value: suggestion)
        }

        /// Where a saved server connects: `user@host` and the port when not 22.
        func savedServerTarget(_ machine: RDMachine) -> String {
            let username = machine.sshLoginUsername(identity: store.associatedIdentity(for: machine))
            var target = username.isEmpty ? machine.remoteAddress : "\(username)@\(machine.remoteAddress)"
            if machine.remotePort != "22" { target += ":\(machine.remotePort)" }
            return target
        }

        func connect() {
            if let parsed {
                TerminalManager.shared.begin(for: parsed)
            } else if let savedServer {
                ServerActions.openTerminal(savedServer.id)
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

        /// Hidden importer kept from the original app: long-press Connect with the
        /// exported data, then again with its key, on the pasteboard.
        func importFromPasteboard() {
            guard let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if let data = importData {
                importData = nil
                do {
                    let result = try store.importPasted(data, key: paste)
                    Indicator.success("Data imported", message: "\(result.summary)")
                } catch {
                    Indicator.error(String(localized: "Could not import: \(error.localizedDescription)"))
                }
            } else if let data = Data(base64Encoded: paste) {
                importData = data
            }
        }
    }

    /// A recent server or command as a chip; a tap connects.
    struct RecentRow: View {
        let record: RayonStore.RecentConnection
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction

        var body: some View {
            Button(action: connect) {
                HStack(spacing: 6) {
                    switch record {
                    case let .command(command):
                        Image(systemName: "terminal")
                        Text(command.command.replacingOccurrences(of: "ssh ", with: ""))
                            .font(.system(size: 13, design: .monospaced))
                    case let .machine(id):
                        Image(systemName: "server.rack")
                        RedactableText(store.machine(id)?.name ?? String(localized: "Deleted server"), redacted: redaction == .all)
                            .font(.system(size: 13))
                    }
                }
                .lineLimit(1)
                .foregroundStyle(.rxInk)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Copy Command") { Pasteboard.copy(record.equivalentSSHCommand) }
                Button("Remove from Recent", role: .destructive) {
                    store.recentRecord.removeAll { $0.id == record.id }
                }
            }
        }

        func connect() {
            switch record {
            case let .command(command): TerminalManager.shared.begin(for: command)
            case let .machine(machine): ServerActions.openTerminal(machine)
            }
        }
    }

#endif
