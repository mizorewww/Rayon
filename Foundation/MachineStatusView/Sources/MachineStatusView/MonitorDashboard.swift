//
//  MonitorDashboard.swift
//  MachineStatusView
//

import MachineStatus
import RayonModule
import SwiftUI

/// The monitor's card grid. Two columns when there is room (System, Processor,
/// Memory, Disks on the left; RX/TX, Network, Graphics on the right), one otherwise.
public struct MonitorDashboard: View {
    @ObservedObject var session: MonitorSession

    public init(session: MonitorSession) {
        self.session = session
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: RX.Space.s4) {
                leftColumn
                rightColumn
            }
            .frame(minWidth: 760)
            VStack(spacing: RX.Space.s4) {
                leftColumn
                rightColumn
            }
        }
    }

    var leftColumn: some View {
        VStack(spacing: RX.Space.s4) {
            SystemCard(session: session)
            ProcessorCard(session: session)
            MemoryCard(session: session)
            DiskCard(session: session)
        }
        .frame(maxWidth: .infinity)
    }

    var rightColumn: some View {
        VStack(spacing: RX.Space.s4) {
            HStack(spacing: RX.Space.s4) {
                ThroughputCard(session: session, direction: .receive)
                ThroughputCard(session: session, direction: .transmit)
            }
            NetworkCard(session: session)
            GraphicsCard(session: session)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Hostname, System, Uptime and Address under the page title.
public struct MonitorFacts: View {
    @ObservedObject var session: MonitorSession
    let redactAddress: Bool

    public init(session: MonitorSession, redactAddress: Bool = false) {
        self.session = session
        self.redactAddress = redactAddress
    }

    public var body: some View {
        let system = session.status.system
        FactsRow([
            .init("Hostname", value: system.hostname.isEmpty ? "—" : system.hostname),
            .init("System", value: system.releaseName.isEmpty ? "—" : system.releaseName),
            .init("Uptime", value: RXFormat.duration(system.uptimeSec)),
            .init("Address", value: session.machine.remoteAddress, monospaced: true, redacted: redactAddress),
        ])
    }
}

/// Small tile for compact layouts (menu bar, iPhone): caption and one number.
public struct MonitorTile: View {
    let title: String
    let value: String
    let unit: String
    let fraction: Double?
    let color: Color

    public init(_ title: String, value: String, unit: String, fraction: Double? = nil, color: Color = .rxAccent) {
        self.title = title
        self.value = value
        self.unit = unit
        self.fraction = fraction
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            CapsLabel(title)
            MetricView(value, unit: unit, size: .md)
            if let fraction {
                UsageBar(fraction: fraction, color: color, height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rxCard(padding: RX.Space.s3)
    }
}

/// CPU, Memory, RX and TX tiles.
public struct MonitorTiles: View {
    @ObservedObject var session: MonitorSession
    let columns: Int

    public init(session: MonitorSession, columns: Int = 2) {
        self.session = session
        self.columns = columns
    }

    public var body: some View {
        let status = session.status
        let cpu = Double(status.processor.summary.sumUsed)
        let memory = status.memoryUsedPercent
        let rx = RXFormat.rate(Double(status.totalReceivePerSecond))
        let tx = RXFormat.rate(Double(status.totalTransmitPerSecond))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: RX.Space.s3), count: columns), spacing: RX.Space.s3) {
            MonitorTile("CPU", value: RXFormat.percent(cpu), unit: "%", fraction: cpu / 100)
            MonitorTile("Memory", value: RXFormat.percent(memory), unit: "%", fraction: memory / 100, color: .rxSeries2)
            MonitorTile("Receive", value: rx.value, unit: rx.unit)
            MonitorTile("Transmit", value: tx.value, unit: tx.unit)
        }
    }
}

/// A single-column monitor for narrow containers (menu bar popover, iPhone).
public struct CompactMonitorView: View {
    @ObservedObject var session: MonitorSession

    public init(session: MonitorSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: RX.Space.s3) {
            MonitorTiles(session: session)
            GraphicsCard(session: session)
            DiskCard(session: session)
        }
    }
}

/// What a monitor shows before its first reading or after it fails.
public struct MonitorPlaceholder: View {
    @ObservedObject var session: MonitorSession
    let retry: (() -> Void)?

    public init(session: MonitorSession, retry: (() -> Void)? = nil) {
        self.session = session
        self.retry = retry
    }

    public var body: some View {
        Group {
            switch session.phase {
            case let .failed(message):
                EmptyStateView(
                    "Cannot reach \(session.machine.name)",
                    systemImage: "exclamationmark.triangle",
                    message: message,
                    actionTitle: retry == nil ? nil : "Try Again",
                    action: retry
                )
            case .closed:
                EmptyStateView("Monitor closed", systemImage: "waveform.path.ecg")
            default:
                VStack(spacing: RX.Space.s3) {
                    ProgressView()
                    Text("Connecting to \(session.machine.name)…")
                        .font(.rxBody)
                        .foregroundStyle(.rxInkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(RX.Space.s6)
            }
        }
        .rxCard()
    }
}
