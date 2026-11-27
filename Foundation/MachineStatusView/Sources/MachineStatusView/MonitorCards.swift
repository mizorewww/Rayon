//
//  MonitorCards.swift
//  MachineStatusView
//
//  The cards of a server's monitor. Each card answers one question with one large
//  number and shows only what Rayon reads from the server's system tools.
//

import MachineStatus
import RayonModule
import SwiftUI

// MARK: - System

public struct SystemCard: View {
    @ObservedObject var session: MonitorSession

    public init(session: MonitorSession) {
        self.session = session
    }

    var system: ServerStatus.SystemInfo { session.status.system }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHead(.init("Load", bundle: .module))
            MetricView(String(format: "%.2f", system.load1), unit: String(localized: "1 min", bundle: .module))
                .padding(.top, RX.Space.s1)
            SubMetricRow([
                .init(.init("5 min", bundle: .module), value: String(format: "%.2f", system.load5)),
                .init(.init("15 min", bundle: .module), value: String(format: "%.2f", system.load15)),
                .init(.init("Processes", bundle: .module), value: "\(system.runningProcs)", unit: String(localized: "/ \(system.totalProcs) running", bundle: .module)),
            ])
            .padding(.top, RX.Space.s5)
        }
        .rxCard()
    }
}

// MARK: - Processor

public struct ProcessorCard: View {
    @ObservedObject var session: MonitorSession
    @State private var showCores = false

    public init(session: MonitorSession) {
        self.session = session
    }

    var processor: ServerStatus.ProcessorInfo { session.status.processor }

    var title: LocalizedStringResource {
        let count = processor.cores.count
        guard count > 0 else { return .init("Processor", bundle: .module) }
        return .init("Processor · \(count) cores", bundle: .module)
    }

    public var body: some View {
        let summary = processor.summary
        let hasCores = !processor.cores.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            CardHead(title) {
                if hasCores {
                    Picker(String(localized: "Summary or Cores", bundle: .module), selection: $showCores) {
                        Text("Summary", bundle: .module).tag(false)
                        Text("Cores", bundle: .module).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            MetricView(RXFormat.oneDecimal(Double(summary.sumUsed)), unit: "%")
                .padding(.top, RX.Space.s1)
            if showCores, hasCores {
                CoreGrid(cores: processor.cores)
                    .padding(.top, RX.Space.s4)
            } else {
                UsageBar([
                    .init(.init("User", bundle: .module), Double(summary.sumUser) / 100, .rxAccent),
                    .init(.init("System", bundle: .module), Double(summary.sumSystem) / 100, .rxSeries2),
                    .init(.init("IO wait", bundle: .module), Double(summary.sumIOWait) / 100, .rxWarning),
                    .init(.init("Nice", bundle: .module), Double(summary.sumNice) / 100, .rxControlBorder),
                ])
                .padding(.top, RX.Space.s3)
                SubMetricRow([
                    .init(.init("User", bundle: .module), value: RXFormat.oneDecimal(Double(summary.sumUser)), unit: "%", swatch: .rxAccent),
                    .init(.init("System", bundle: .module), value: RXFormat.oneDecimal(Double(summary.sumSystem)), unit: "%", swatch: .rxSeries2),
                    .init(.init("IO wait", bundle: .module), value: RXFormat.oneDecimal(Double(summary.sumIOWait)), unit: "%", swatch: .rxWarning),
                    .init(.init("Nice", bundle: .module), value: RXFormat.oneDecimal(Double(summary.sumNice)), unit: "%", swatch: .rxControlBorder),
                ])
                .padding(.top, RX.Space.s5)
            }
        }
        .rxCard()
    }
}

/// Per-core usage tiles; eight per row, shrinking for large core counts.
public struct CoreGrid: View {
    let cores: [ServerStatus.ProcessPercentInfo]

    public init(cores: [ServerStatus.ProcessPercentInfo]) {
        self.cores = cores
    }

    public var body: some View {
        if cores.isEmpty {
            HelpText(.init("No data", bundle: .module))
        } else {
            let perRow = cores.count > 64 ? 16 : 8
            let tileHeight: CGFloat = cores.count > 64 ? 28 : 44
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: perRow), spacing: 6) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, core in
                    CoreTile(index: index, percent: Double(core.sumUsed), height: tileHeight)
                }
            }
        }
    }
}

// MARK: - Memory

public struct MemoryCard: View {
    @ObservedObject var session: MonitorSession
    @State private var showSwap = false

    public init(session: MonitorSession) {
        self.session = session
    }

    var memory: ServerStatus.MemoryInfo { session.status.memory }

    public var body: some View {
        let status = session.status
        let total = Double(memory.memTotal)
        let swapTotal = Double(memory.swapTotal)
        let headerSize = showSwap ? swapTotal : total
        VStack(alignment: .leading, spacing: 0) {
            CardHead(headerSize > 0 ? .init("Memory · \(kB(headerSize))", bundle: .module) : .init("Memory", bundle: .module)) {
                Picker(String(localized: "RAM or Swap", bundle: .module), selection: $showSwap) {
                    Text("RAM", bundle: .module).tag(false)
                    Text("Swap", bundle: .module).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if showSwap {
                let swapUsed = max(0, swapTotal - Double(memory.swapFree))
                MetricView(RXFormat.percent(swapTotal > 0 ? swapUsed / swapTotal * 100 : 0), unit: "%")
                    .padding(.top, RX.Space.s1)
                SplitBar([
                    (swapUsed, .rxAccent),
                    (max(0, swapTotal - swapUsed), .rxSurfaceSunken),
                ])
                .padding(.top, RX.Space.s3)
                HStack(spacing: RX.Space.s4) {
                    LegendItem(.init("Used", bundle: .module), value: kB(swapUsed), color: .rxAccent)
                    LegendItem(.init("Free", bundle: .module), value: kB(Double(memory.swapFree)), color: .rxSurfaceSunken, outlined: true)
                }
                .padding(.top, RX.Space.s3)
                if swapTotal <= 0 {
                    HelpText(.init("No swap", bundle: .module))
                        .padding(.top, RX.Space.s3)
                }
            } else {
                MetricView(RXFormat.oneDecimal(status.memoryUsedPercent), unit: "%")
                    .padding(.top, RX.Space.s1)
                SplitBar([
                    (status.memoryUsedKB, .rxAccent),
                    (status.memoryCacheKB, .rxSeries2),
                    (Double(memory.memFree), .rxSurfaceSunken),
                ])
                .padding(.top, RX.Space.s3)
                .accessibilityLabel(Text("\(kB(status.memoryUsedKB)) used, \(kB(status.memoryCacheKB)) cache, \(kB(Double(memory.memFree))) free", bundle: .module))
                FlowRow {
                    LegendItem(.init("Used", bundle: .module), value: kB(status.memoryUsedKB), color: .rxAccent)
                    LegendItem(.init("Cache", bundle: .module), value: kB(status.memoryCacheKB), color: .rxSeries2)
                    LegendItem(.init("Free", bundle: .module), value: kB(Double(memory.memFree)), color: .rxSurfaceSunken, outlined: true)
                }
                .padding(.top, RX.Space.s3)
            }
        }
        .rxCard()
    }

    func kB(_ value: Double) -> String {
        RXFormat.bytesString(value * 1024)
    }
}

/// Wraps short items onto a second line when the card is narrow.
struct FlowRow<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RX.Space.s4) { content }
            VStack(alignment: .leading, spacing: RX.Space.s2) { content }
        }
    }
}

// MARK: - Disks

public struct DiskCard: View {
    @ObservedObject var session: MonitorSession
    let limit: Int?

    public init(session: MonitorSession, limit: Int? = nil) {
        self.session = session
        self.limit = limit
    }

    public var body: some View {
        let elements = session.status.fileSystem.elements
        let shown = limit.map { Array(elements.prefix($0)) } ?? elements
        VStack(alignment: .leading, spacing: 0) {
            CardHead(.init("Disks", bundle: .module))
            if shown.isEmpty {
                HelpText(.init("No data", bundle: .module))
                    .padding(.top, RX.Space.s2)
            } else {
                VStack(spacing: RX.Space.s3) {
                    ForEach(shown) { element in
                        UsageListRow(
                            name: element.mountPoint,
                            value: "\(RXFormat.percent(Double(element.percent)))%",
                            detail: String(localized: "\(element.used) of \(element.size)", bundle: .module)
                        ) {
                            UsageBar(fraction: Double(element.percent) / 100, thresholds: true)
                        }
                    }
                }
                .padding(.top, RX.Space.s2)
            }
        }
        .rxCard()
    }
}

/// A row of a usage list: monospaced name, bold value and detail, a bar underneath.
struct UsageListRow<Bar: View>: View {
    let name: String
    let value: String
    let detail: String
    let bar: Bar

    init(name: String, value: String, detail: String, @ViewBuilder bar: () -> Bar) {
        self.name = name
        self.value = value
        self.detail = detail
        self.bar = bar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: RX.Space.s2) {
                Text(name)
                    .font(.rxCode)
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: RX.Space.s2)
                Text(value)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.rxInk)
                if !detail.isEmpty {
                    Text(verbatim: "· \(detail)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                }
            }
            bar
        }
    }
}

// MARK: - Network

/// Receive or transmit rate with a sparkline of the samples collected in this session.
public struct ThroughputCard: View {
    public enum Direction {
        case receive
        case transmit
    }

    @ObservedObject var session: MonitorSession
    let direction: Direction
    let height: CGFloat

    public init(session: MonitorSession, direction: Direction, height: CGFloat = 200) {
        self.session = session
        self.direction = direction
        self.height = height
    }

    public var body: some View {
        let isReceive = direction == .receive
        let samples = isReceive ? session.history.receive : session.history.transmit
        let current = Double(isReceive ? session.status.totalReceivePerSecond : session.status.totalTransmitPerSecond)
        let peak = samples.max() ?? 0
        let rate = RXFormat.rate(current)
        VStack(alignment: .leading, spacing: 0) {
            CardHead(isReceive ? .init("Receive", bundle: .module) : .init("Transmit", bundle: .module)) {
                if peak > 0 {
                    HintText(.init("peak \(RXFormat.rateString(peak))", bundle: .module))
                }
            }
            .padding(.horizontal, RX.Space.s4)
            .padding(.top, RX.Space.s4)
            MetricView(rate.value, unit: rate.unit)
                .padding(.horizontal, RX.Space.s4)
                .padding(.top, RX.Space.s1)
            Spacer(minLength: RX.Space.s2)
            Sparkline(
                samples,
                color: isReceive ? .rxSeries2 : .rxAccent,
                fill: isReceive ? .rxSeries2Fill : .rxAccentFill
            )
            .frame(height: height * 0.42)
        }
        .frame(height: height)
        .rxCardChrome()
    }
}

public struct NetworkCard: View {
    @ObservedObject var session: MonitorSession

    public init(session: MonitorSession) {
        self.session = session
    }

    public var body: some View {
        let elements = session.status.network.elements.sorted { ($0.rxBytesPerSec + $0.txBytesPerSec) > ($1.rxBytesPerSec + $1.txBytesPerSec) }
        let peak = Double(max(1, elements.map { max($0.rxBytesPerSec, $0.txBytesPerSec) }.max() ?? 1))
        VStack(alignment: .leading, spacing: 0) {
            // Totals live in the Receive and Transmit cards beside this one.
            CardHead(.init("Network", bundle: .module))
            if elements.isEmpty {
                HelpText(.init("No data", bundle: .module))
                    .padding(.top, RX.Space.s2)
            } else {
                VStack(spacing: RX.Space.s3) {
                    ForEach(elements) { element in
                        UsageListRow(
                            name: element.device,
                            value: "↓ \(RXFormat.rateString(Double(element.rxBytesPerSec)))",
                            detail: "↑ \(RXFormat.rateString(Double(element.txBytesPerSec)))"
                        ) {
                            UsageBar([
                                .init(.init("Receive", bundle: .module), Double(element.rxBytesPerSec) / peak / 2, .rxSeries2),
                                .init(.init("Transmit", bundle: .module), Double(element.txBytesPerSec) / peak / 2, .rxAccent),
                            ])
                        }
                    }
                }
                .padding(.top, RX.Space.s2)
            }
        }
        .rxCard()
    }
}

// MARK: - Processes

/// The busiest processes, by CPU or by memory, as the server's `ps` reports them.
public struct ProcessesCard: View {
    @ObservedObject var session: MonitorSession
    @State private var byMemory = false

    public init(session: MonitorSession) {
        self.session = session
    }

    public var body: some View {
        let processes = session.status.processes
        let rows = byMemory ? processes.byMemory : processes.byCPU
        VStack(alignment: .leading, spacing: 0) {
            CardHead(.init("Top processes", bundle: .module)) {
                Picker(String(localized: "CPU or Memory", bundle: .module), selection: $byMemory) {
                    Text("CPU", bundle: .module).tag(false)
                    Text("Memory", bundle: .module).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if rows.isEmpty {
                HelpText(.init("No data", bundle: .module))
                    .padding(.top, RX.Space.s2)
            } else {
                VStack(spacing: RX.Space.s2) {
                    HStack(spacing: RX.Space.s2) {
                        CapsLabel(.init("Name", bundle: .module))
                        Spacer(minLength: RX.Space.s2)
                        CapsLabel(.init("CPU", bundle: .module))
                            .frame(width: ProcessRow.cpuWidth, alignment: .trailing)
                        CapsLabel(.init("Memory", bundle: .module))
                            .frame(width: ProcessRow.memoryWidth, alignment: .trailing)
                    }
                    ForEach(rows) { process in
                        ProcessRow(process: process, byMemory: byMemory)
                    }
                }
                .padding(.top, RX.Space.s2)
            }
        }
        .rxCard()
    }
}

/// Name, then owner and PID, which give way first when the card is narrow;
/// CPU and memory in fixed columns, the sorted one in bold.
struct ProcessRow: View {
    static let cpuWidth: CGFloat = 52
    static let memoryWidth: CGFloat = 72

    let process: ServerStatus.TopProcess
    let byMemory: Bool

    var cpu: String {
        process.cpuPercent.map { "\(RXFormat.oneDecimal($0))%" } ?? "—"
    }

    var memory: String {
        if let resident = process.residentKB {
            return RXFormat.bytesString(resident * 1024)
        }
        return process.memoryPercent.map { "\(RXFormat.oneDecimal($0))%" } ?? "—"
    }

    var body: some View {
        HStack(spacing: RX.Space.s2) {
            Text(process.command)
                .font(.rxCode)
                .foregroundStyle(.rxInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Text(verbatim: process.user.isEmpty ? "\(process.pid)" : "\(process.user) · \(process.pid)")
                .font(.rxAxis)
                .foregroundStyle(.rxInkTertiary)
                .lineLimit(1)
            Spacer(minLength: RX.Space.s2)
            value(cpu, emphasized: !byMemory)
                .frame(width: Self.cpuWidth, alignment: .trailing)
            value(memory, emphasized: byMemory)
                .frame(width: Self.memoryWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(process.user.isEmpty
            ? Text("\(process.command), PID \(process.pid), CPU \(cpu), memory \(memory)", bundle: .module)
            : Text("\(process.command), PID \(process.pid), \(process.user), CPU \(cpu), memory \(memory)", bundle: .module))
    }

    func value(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: emphasized ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(emphasized ? Color.rxInk : Color.rxInkSecondary)
            .lineLimit(1)
    }
}

// MARK: - Graphics

/// One row per GPU from nvidia-smi. Hidden when the server has no GPU.
public struct GraphicsCard: View {
    @ObservedObject var session: MonitorSession

    public init(session: MonitorSession) {
        self.session = session
    }

    public var body: some View {
        if let graphics = session.status.graphics, !graphics.units.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardHead(.init("Graphics · \(graphics.units.count) GPUs", bundle: .module)) {
                    HintText(.init("Driver \(graphics.version)", bundle: .module))
                }
                VStack(spacing: RX.Space.s4) {
                    ForEach(graphics.units) { unit in
                        GPURow(unit: unit)
                    }
                }
                .padding(.top, RX.Space.s2)
            }
            .rxCard()
        }
    }
}

struct GPURow: View {
    let unit: ServerStatus.SingleGraphicsInfo

    var body: some View {
        let utilisation = Double(unit.utilization.gpu_util)
        let vram = unit.memory.total > 0 ? Double(unit.memory.used / unit.memory.total) * 100 : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: RX.Space.s2) {
                Text(unit.name)
                    .font(.rxBodyStrong)
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                Spacer(minLength: RX.Space.s2)
                Text("Fan \(unit.fan_speed)", bundle: .module)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.rxInkSecondary)
                    .lineLimit(1)
            }
            labeledBar(.init("GPU", bundle: .module), percent: utilisation, color: .rxAccent)
            labeledBar(.init("VRAM", bundle: .module), percent: vram, color: .rxSeries2)
            if !unit.vbios_version.isEmpty {
                HintText(.init("vbios \(unit.vbios_version)", bundle: .module))
            }
        }
    }

    func labeledBar(_ title: LocalizedStringResource, percent: Double, color: Color) -> some View {
        HStack(spacing: RX.Space.s2) {
            CapsLabel(title)
                .frame(width: 40, alignment: .leading)
            UsageBar(fraction: percent / 100, color: color, thresholds: true)
            Text(verbatim: "\(RXFormat.percent(percent))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.rxInk)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
