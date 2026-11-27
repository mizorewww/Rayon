//
//  BatchRunSheet+macOS.swift
//  Rayon
//
//  Running one snippet on several servers: per-server state and time on the left
//  (Done `success`, Running `accent`, Failed `danger`), that server's output on the
//  right, overall progress, Stop and Done.
//

#if os(macOS)
    import Combine
    import RayonModule
    import RayonTerminal
    import SwiftUI

    struct BatchRunSheet: View {
        let snippet: RDSnippet
        let machines: [RDMachine.ID]
        let close: () -> Void

        @StateObject private var context: BatchSnippetExecContext
        @State private var selection: RDMachine.ID?

        init(snippet: RDSnippet, machines: [RDMachine.ID], close: @escaping () -> Void) {
            self.snippet = snippet
            self.machines = machines
            self.close = close
            _context = StateObject(wrappedValue: BatchSnippetExecContext(snippet: snippet, machines: machines))
            _selection = State(initialValue: machines.first)
        }

        var completedCount: Int { context.completedCount }
        var finished: Bool { completedCount >= machines.count }

        var body: some View {
            SheetScaffold("Run \(snippet.name)") {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    HStack(alignment: .top, spacing: RX.Space.s3) {
                        serverList
                            .frame(width: 220)
                        output
                    }
                    .frame(height: 320)
                    RXProgressBar(machines.isEmpty ? 1 : Double(completedCount) / Double(machines.count))
                }
            } footer: {
                Text("\(completedCount) of \(machines.count) finished")
                    .font(.rxBody.monospacedDigit())
                    .foregroundStyle(.rxInkSecondary)
                Spacer()
                if !finished {
                    Button("Stop") { context.stopAll() }
                        .buttonStyle(.rx)
                }
                Button("Done") {
                    if finished {
                        close()
                    } else {
                        Indicator.confirm(
                            message: "Stop running \(snippet.name)?",
                            confirmTitle: "Stop and Close",
                            destructive: true,
                            skippable: true
                        ) { confirmed in
                            guard confirmed else { return }
                            context.stopAll()
                            close()
                        }
                    }
                }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: 820)
            .onAppear { context.start() }
        }

        var serverList: some View {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(machines, id: \.self) { machine in
                        let state = context.state(for: machine)
                        Button {
                            selection = machine
                        } label: {
                            HStack(spacing: RX.Space.s2) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(context.names[machine] ?? "Unknown server")
                                        .font(.rxBody)
                                        .foregroundStyle(.rxInk)
                                        .lineLimit(1)
                                    stateLabel(state)
                                }
                                Spacer()
                                duration(state)
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.rxInkSecondary)
                            }
                            .padding(.horizontal, RX.Space.s2)
                            .frame(height: RX.tableRowHeight)
                            .rxRowBackground(selected: selection == machine)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(RX.Space.s2)
            }
            .background(
                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                    .strokeBorder(Color.rxHairline, lineWidth: 1)
            )
        }

        @ViewBuilder
        func stateLabel(_ state: BatchSnippetExecContext.MachineState) -> some View {
            switch state {
            case .waiting: EmptyView()
            case .running: ProgressView().controlSize(.mini)
            case .done: Image(systemName: "checkmark").foregroundStyle(.rxSuccess).accessibilityLabel("Done")
            case .failed: Image(systemName: "xmark").foregroundStyle(.rxDanger).accessibilityLabel("Failed")
            }
        }

        @ViewBuilder
        func duration(_ state: BatchSnippetExecContext.MachineState) -> some View {
            switch state {
            case .waiting:
                EmptyView()
            case let .running(since):
                TimelineView(.periodic(from: since, by: 0.1)) { timeline in
                    Text(Self.seconds(timeline.date.timeIntervalSince(since)))
                }
            case let .done(duration), let .failed(duration):
                Text(Self.seconds(duration))
            }
        }

        static func seconds(_ seconds: TimeInterval) -> String {
            String(format: "%.1f s", max(0, seconds))
        }

        @ViewBuilder var output: some View {
            ZStack {
                ForEach(machines, id: \.self) { machine in
                    BatchOutputView(machine: machine)
                        .opacity(selection == machine ? 1 : 0)
                        .allowsHitTesting(selection == machine)
                }
            }
            .padding(RX.Space.s2)
            .background(
                RoundedRectangle(cornerRadius: RX.Radius.md, style: .continuous)
                    .fill(Color.rxTerminalBackground)
            )
            .environmentObject(context)
        }
    }

    /// One server's output in a terminal surface.
    private struct BatchOutputView: View {
        let machine: RDMachine.ID
        @EnvironmentObject var context: BatchSnippetExecContext

        @State private var terminalId = UUID()
        @State private var terminalView = RayonTerminalView()

        private func flushPending() {
            let incoming = context.requestBuffer(for: terminalId, machine: machine)
            if !incoming.isEmpty {
                terminalView.write(incoming)
            }
        }

        var body: some View {
            terminalView
                // A task, unlike onReceive, keeps one subscription for the
                // view's life, so an update never drops a throttled flush.
                .task {
                    for await _ in context.outputChanges(for: machine).values {
                        flushPending()
                    }
                }
        }
    }

#endif
