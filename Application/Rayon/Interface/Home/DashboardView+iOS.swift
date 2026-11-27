//
//  DashboardView+iOS.swift
//  Rayon
//
//  Every saved server as a tile; a tap offers its actions. A tab of its own
//  on iPhone, the row under Home in the iPad sidebar.
//

#if os(iOS)
    import MachineStatusView
    import RayonModule
    import SwiftUI

    struct DashboardView: View {
        @EnvironmentObject var store: RayonStore
        @ObservedObject var monitors = MonitorCenter.shared
        @State private var openNewServer = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    SectionTitle("Servers", count: store.machines.count) {
                        if !store.machines.isEmpty {
                            Button {
                                ServerActions.batchStartup()
                            } label: {
                                Label("Batch Startup", systemImage: "wind")
                            }
                            .buttonStyle(.rx(size: .small))
                        }
                    }
                    if store.machines.isEmpty {
                        EmptyStateView(
                            "No servers yet",
                            systemImage: "server.rack",
                            actionTitle: "New Server"
                        ) {
                            openNewServer = true
                        }
                        .rxCard()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: RX.Space.s3)], spacing: RX.Space.s3) {
                            ForEach(store.machines) { machine in
                                ServerTile(machine: machine.id)
                            }
                        }
                    }
                }
                .padding(RX.Space.s4)
            }
            .background(RXBackdrop().ignoresSafeArea())
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem {
                    Button {
                        openNewServer = true
                    } label: {
                        Label("New Server", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $openNewServer) {
                NavigationStack { EditMachineView() }
            }
        }
    }

    /// A server at a glance: name, address, state, CPU and memory while monitored.
    struct ServerTile: View {
        let machine: RDMachine.ID
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction
        @ObservedObject var monitors = MonitorCenter.shared

        var body: some View {
            let read = (store.machine(machine) ?? RDMachine())
            Menu {
                ServerMenuItems(machine: machine)
            } label: {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            RedactableText(read.name, redacted: redaction == .all)
                                .font(.headline)
                                .foregroundStyle(.rxInk)
                                .lineLimit(1)
                            RedactableText(read.remoteAddress, redacted: redaction != .none)
                                .font(.rxCode)
                                .foregroundStyle(.rxInkSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    if let session = monitors.session(for: machine) {
                        LiveTileBars(session: session)
                    } else {
                        HStack {
                            CapsLabel("Last used")
                            Spacer()
                            Text(RXFormat.relative(read.lastConnection))
                                .font(.footnote)
                                .foregroundStyle(.rxInkSecondary)
                        }
                    }
                }
                .multilineTextAlignment(.leading)
                .rxCard()
            }
            .buttonStyle(.plain)
        }
    }

    private struct LiveTileBars: View {
        @ObservedObject var session: MonitorSession
        var body: some View {
            let cpu = Double(session.status.processor.summary.sumUsed)
            let memory = session.status.memoryUsedPercent
            VStack(spacing: RX.Space.s2) {
                bar("CPU", cpu, .rxAccent)
                bar("Memory", memory, .rxSeries2)
            }
        }

        func bar(_ title: String, _ percent: Double, _ color: Color) -> some View {
            HStack(spacing: RX.Space.s2) {
                CapsLabel(title).frame(width: 56, alignment: .leading)
                UsageBar(fraction: percent / 100, color: color)
                Text("\(RXFormat.percent(percent))%")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

#endif
