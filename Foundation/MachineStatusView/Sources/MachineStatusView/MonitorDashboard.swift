//
//  MonitorDashboard.swift
//  MachineStatusView
//

import MachineStatus
import RayonModule
import SwiftUI

/// The monitor's card grid. Two columns when there is room (Load, Processor,
/// Memory, Disks on the left; Receive and Transmit, Network, Top processes,
/// Graphics on the right),
/// one otherwise.
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
            // The cards arrive one after another, across both columns.
            SystemCard(session: session).rxRise(0)
            ProcessorCard(session: session).rxRise(2)
            MemoryCard(session: session).rxRise(4)
            DiskCard(session: session).rxRise(6)
        }
        .frame(maxWidth: .infinity)
    }

    var rightColumn: some View {
        VStack(spacing: RX.Space.s4) {
            HStack(spacing: RX.Space.s4) {
                ThroughputCard(session: session, direction: .receive)
                ThroughputCard(session: session, direction: .transmit)
            }
            .rxRise(1)
            NetworkCard(session: session).rxRise(3)
            ProcessesCard(session: session).rxRise(5)
            GraphicsCard(session: session).rxRise(7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Hostname, OS, Uptime and Address under the page title.
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
            .init(.init("Hostname", bundle: .module), value: system.hostname.isEmpty ? "—" : system.hostname),
            .init(.init("OS", bundle: .module), value: system.releaseName.isEmpty ? "—" : system.releaseName),
            .init(.init("Uptime", bundle: .module), value: RXFormat.duration(system.uptimeSec)),
            .init(.init("Address", bundle: .module), value: session.machine.remoteAddress, monospaced: true, redacted: redactAddress),
        ])
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
                    .init("Can't connect", bundle: .module),
                    systemImage: "exclamationmark.triangle",
                    message: "\(message)",
                    actionTitle: retry == nil ? nil : .init("Try Again", bundle: .module),
                    action: retry
                )
            case .unavailable:
                EmptyStateView(
                    .init("Status isn't available", bundle: .module),
                    systemImage: "waveform.path.ecg",
                    message: .init("This server doesn't run the status script; it needs a POSIX shell.", bundle: .module),
                    actionTitle: retry == nil ? nil : .init("Try Again", bundle: .module),
                    action: retry
                )
            case .closed:
                EmptyStateView(.init("Monitor closed", bundle: .module), systemImage: "waveform.path.ecg")
            default:
                VStack(spacing: RX.Space.s3) {
                    ProgressView()
                        .rxSpinner()
                    Text("Connecting…", bundle: .module)
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
