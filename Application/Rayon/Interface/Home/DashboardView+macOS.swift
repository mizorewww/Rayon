//
//  DashboardView+macOS.swift
//  Rayon
//
//  Every saved server as a tile: the page under Home in the sidebar. Every
//  tile is the same size and names its actions: Connect, Files, Monitor.
//

#if os(macOS)
    import MachineStatusView
    import RayonModule
    import SwiftUI

    struct DashboardView: View {
        @EnvironmentObject var store: RayonStore

        var body: some View {
            ScrollView {
                serversSection
                    .padding(RX.Space.s6)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.25), value: store.machines.map(\.id))
            }
            .pageChrome()
            // No toolbar "+": the grid ends in the New Server tile (and the empty
            // state offers it), so a second button would do the same thing.
        }

        @ViewBuilder var serversSection: some View {
            if store.machines.isEmpty {
                EmptyStateView(
                    "Save a server to reach it in one click",
                    systemImage: "server.rack",
                    message: "Saved servers keep their address, port and identity, and open a terminal, files or a monitor.",
                    actionTitle: "New Server"
                ) {
                    AppRouter.shared.presentNewServer = true
                }
                .frame(maxWidth: 640)
                .rxCard()
            } else {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    // Every server is in the grid; the sidebar's Servers has the
                    // count and the table.
                    SectionTitle("Servers")
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 310), spacing: RX.Space.s4)],
                        spacing: RX.Space.s4
                    ) {
                        ForEach(Array(store.machines.enumerated()), id: \.element.id) { index, machine in
                            ServerTile(machine: machine.id)
                                .rxRise(index)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        }
                        NewServerTile()
                    }
                }
            }
        }
    }

    // MARK: - Tiles

    /// Every tile in the grid, the New Server tile included, has this height, so rows
    /// line up whether or not a server is being monitored.
    private let serverTileHeight: CGFloat = 168

    /// A server at a glance: name, address, state, CPU and memory while monitored,
    /// and its actions by name. Clicking the tile connects; right-click for more.
    struct ServerTile: View {
        let machine: RDMachine.ID
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        // Observed so the dot follows a terminal opening or closing, the same
        // subscription SessionTabs makes.
        @ObservedObject var terminals = TerminalManager.shared
        /// For a UU device's online state.
        @ObservedObject private var account = UURemoteAccount.shared
        @State private var hovered = false

        var body: some View {
            let read = (store.machine(machine) ?? RDMachine())
            ServerLiveReader(machine: machine) { state in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: RX.Space.s2) {
                        VStack(alignment: .leading, spacing: 2) {
                            RedactableText(read.name, redacted: redaction == .all)
                                .font(.rxBodyStrong)
                                .foregroundStyle(.rxInk)
                                .lineLimit(1)
                            if read.isUURemoteDevice {
                                // Its address would be the device id.
                                Text(uuStatus(read))
                                    .font(.rxBody)
                                    .foregroundStyle(.rxInkSecondary)
                                    .lineLimit(1)
                            } else {
                                RedactableText(read.remoteAddress, redacted: redaction != .none)
                                    .font(.rxCode)
                                    .foregroundStyle(.rxInkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: RX.Space.s2)
                        if connected {
                            StatusDot(.success, size: .small)
                                .padding(.top, 6)
                                .help("A terminal is open")
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Spacer(minLength: RX.Space.s2)
                    Group {
                        if let cpu = state.cpu, let memory = state.memory {
                            VStack(spacing: 6) {
                                tileBar("CPU", percent: cpu, color: .rxAccent)
                                tileBar("Memory", percent: memory, color: .rxSeries2)
                            }
                            .transition(.opacity)
                        } else {
                            VStack(spacing: 6) {
                                infoRow("Last used", RXFormat.relative(read.lastConnection))
                                infoRow("Identity", identityName(read))
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: state.cpu == nil)
                    Spacer(minLength: RX.Space.s3)
                    actions
                }
                .frame(height: serverTileHeight - RX.Space.s4 * 2)
            }
            .rxCard()
            .overlay(
                RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)
                    .strokeBorder(Color.rxAccent.opacity(hovered ? 0.35 : 0), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovered ? 0.12 : 0), radius: 16, y: 8)
            .scaleEffect(hovered ? 1.01 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovered)
            .contentShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous))
            .onHover { hovered = $0 }
            .onTapGesture { if !offline { connect() } }
            .contextMenu { ServerContextMenu(machine: machine) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
        }

        var connected: Bool {
            terminals.sessionContexts.contains { $0.remoteType == .machine && $0.machine.id == machine && !$0.closed }
        }

        var actions: some View {
            HStack(spacing: RX.Space.s1) {
                // Named like the page switcher: Terminal, Files, Monitor.
                Button(action: connect) {
                    Label(ServerTool.terminal.title, systemImage: ServerTool.terminal.systemImage)
                }
                .buttonStyle(.rx(.primary, size: .small))
                .help(offline ? "The device is offline in UU Remote" : ServerTool.terminal.help(for: (store.machine(machine) ?? RDMachine())))
                .disabled(offline)
                // What the server can show (a UU device: its desktop); past two,
                // as icons, so none is cut short.
                let others = ServerTool.available(for: (store.machine(machine) ?? RDMachine())).filter { $0 != .terminal && $0 != .editor }
                ForEach(others) { tool in
                    toolButton(tool, iconOnly: others.count > 2)
                }
                Spacer(minLength: 0)
                RXMenuButton("More", systemImage: "ellipsis", kind: .plain, size: .small, iconOnly: true) {
                    ServerContextMenu(machine: machine, includesTools: false)
                }
            }
        }

        func toolButton(_ tool: ServerTool, iconOnly: Bool = false) -> some View {
            Button {
                tool.show(machine)
            } label: {
                Label(tool.title, systemImage: tool.systemImage)
            }
            .buttonStyle(.rx(size: .small, iconOnly: iconOnly))
            .help(offline ? "The device is offline in UU Remote" : tool.help(for: (store.machine(machine) ?? RDMachine())))
            .disabled(offline)
        }

        /// A UU device the account lists as offline: nothing on it can open.
        var offline: Bool {
            let read = (store.machine(machine) ?? RDMachine())
            guard read.isUURemoteDevice else { return false }
            return account.devices.first { $0.deviceID == read.uuDeviceID }?.isOnline == false
        }

        /// "UU Remote · Online", from the account's last refresh.
        func uuStatus(_ machine: RDMachine) -> String {
            guard let device = account.devices.first(where: { $0.deviceID == machine.uuDeviceID }) else {
                return "UU Remote"
            }
            return device.isOnline ? "UU Remote · Online" : "UU Remote · Offline"
        }

        /// Shows the server's terminal, opening one if none is open.
        func connect() {
            ServerTool.terminal.show(machine)
        }

        func identityName(_ machine: RDMachine) -> String {
            guard let uid = machine.associatedIdentity else {
                // The server's own user name, tried with each automatic identity.
                return machine.sshUsernameOverride.map { "\($0) · Automatic" } ?? "Automatic"
            }
            let identity = (store.identity(uid) ?? RDIdentity())
            return identity.username.isEmpty ? "Missing" : machine.sshLoginUsername(identity: identity)
        }

        func infoRow(_ title: String, _ value: String) -> some View {
            HStack {
                CapsLabel(title)
                Spacer()
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(.rxInkSecondary)
                    .lineLimit(1)
            }
            .frame(height: 16)
        }

        func tileBar(_ title: String, percent: Double, color: Color) -> some View {
            HStack(spacing: RX.Space.s2) {
                CapsLabel(title)
                    .frame(width: 56, alignment: .leading)
                UsageBar(fraction: percent / 100, color: color)
                Text("\(RXFormat.percent(percent))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(height: 16)
        }
    }

    /// The dashed tile that ends the server grid, the same size as a server tile.
    struct NewServerTile: View {
        @State private var hovered = false

        var body: some View {
            Button {
                AppRouter.shared.presentNewServer = true
            } label: {
                VStack(spacing: RX.Space.s2) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .scaleEffect(hovered ? 1.15 : 1)
                    Text("New Server")
                        .font(.rxBody)
                }
                .foregroundStyle(hovered ? Color.rxAccent : Color.rxInkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: serverTileHeight)
                .background(
                    RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(hovered ? Color.rxAccent : Color.rxControlBorder)
                )
                .background(
                    RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)
                        .fill(Color.rxAccent.opacity(hovered ? 0.06 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
            .help("Add a server")
        }
    }

#endif
