//
//  HomeView.swift
//  mRayon
//
//  Home, laid out as the first Rayon had it: the app icon, Quick Connect,
//  recent connections and the version, over a soft glow with drifting dots.
//  The server tiles are on Dashboard.
//

import MachineStatusView
import RayonModule
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: RX.Space.s4)
                    QuickConnectCard()
                    if store.storeRecent, !store.recentRecord.isEmpty {
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
                if !store.reducedViewEffects {
                    RXStarfield()
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
    @State private var command = ""
    @State private var suggestion: String?
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
                    TextField("ssh root@www.example.com -p 22 ↵", text: $command)
                        .font(.system(.headline, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(connect)
                        .onChange(of: command) { newValue in
                            if newValue.hasPrefix("ssh ssh ") { command.removeFirst("ssh ".count) }
                            refreshSuggestion()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.thickMaterial)
                                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        )
                    Button(action: connect) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.rxOnAccent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.rxAccent))
                    }
                    .disabled(!canConnect)
                    .opacity(canConnect ? 1 : 0.35)
                    .simultaneousGesture(LongPressGesture().onEnded { _ in importFromPasteboard() })
                    .accessibilityLabel("Connect")
                }
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
                store.saveTemporarySession.toggle()
            } label: {
                Label("Record Command", systemImage: store.saveTemporarySession ? "checkmark.square.fill" : "square")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(store.saveTemporarySession ? Color.rxAccent : Color.rxInkSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!store.storeRecent)
            .opacity(store.storeRecent ? 1 : 0.5)
            .accessibilityValue(store.saveTemporarySession ? "On" : "Off")
            // Said once a command is typed: before, it read as an error
            // on a page with nothing wrong yet.
            if store.identityGroupForAutoAuth.isEmpty, !command.isEmpty {
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
            RayonStore.overrideImport(from: data, key: paste)
        } else if let data = Data(base64Encoded: paste) {
            importData = data
        }
    }
}

/// A recent server or command as a chip; a tap connects.
struct RecentRow: View {
    let record: RayonStore.RecentConnection
    @EnvironmentObject var store: RayonStore

    var body: some View {
        Button(action: connect) {
            HStack(spacing: 6) {
                switch record {
                case let .command(command):
                    Image(systemName: "terminal")
                    Text(command.command.replacingOccurrences(of: "ssh ", with: ""))
                        .font(.system(size: 13, design: .monospaced))
                case let .machine(id):
                    let machine = store.machineGroup[id]
                    Image(systemName: "server.rack")
                    RedactableText(machine.isNotPlaceholder() ? machine.name : "Deleted server", redacted: store.machineRedacted == .all)
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
            Button("Copy Command") { UIBridge.sendPasteboard(str: record.equivalentSSHCommand) }
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
