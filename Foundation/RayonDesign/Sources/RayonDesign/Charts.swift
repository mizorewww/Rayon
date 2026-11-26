//
//  Charts.swift
//  RayonDesign
//
//  Usage bars, split bars, legends, sparklines and core tiles. The bars
//  and sparklines are Swift Charts marks.
//

import Charts
import SwiftUI

/// Usage color for disks and VRAM: `warning` at 75%, `danger` at 90%.
public func rxUsageColor(_ percent: Double, base: Color = .rxAccent) -> Color {
    if percent >= 90 { return .rxDanger }
    if percent >= 75 { return .rxWarning }
    return base
}

/// A 6pt rounded track on `surface-sunken` with one or more segments.
public struct UsageBar: View {
    public struct Segment {
        /// What VoiceOver names the segment by; a single-value bar needs none.
        let label: String?
        let fraction: Double
        let color: Color

        public init(_ label: String? = nil, _ fraction: Double, _ color: Color) {
            self.label = label
            self.fraction = fraction
            self.color = color
        }
    }

    let segments: [Segment]
    let height: CGFloat

    public init(_ segments: [Segment], height: CGFloat = 6) {
        self.segments = segments
        self.height = height
    }

    /// A single-value bar; pass `thresholds` to turn it `warning` / `danger` past 75% / 90%.
    public init(fraction: Double, color: Color = .rxAccent, thresholds: Bool = false, height: CGFloat = 6) {
        let clamped = max(0, min(1, fraction.isFinite ? fraction : 0))
        let tint = thresholds ? rxUsageColor(clamped * 100, base: color) : color
        segments = [Segment(nil, clamped, tint)]
        self.height = height
    }

    public var body: some View {
        StackedBar(
            parts: segments.map { (min(1, max(0, $0.fraction.isFinite ? $0.fraction : 0)), $0.color) },
            domain: 1,
            cornerRadius: height / 2
        )
        .frame(height: height)
        .background(Capsule().fill(Color.rxSurfaceSunken))
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.3), value: segments.map(\.fraction))
        .accessibilityElement()
        .accessibilityValue(accessibilityValue)
    }

    /// "User 12%, System 4%", or just "45%" for a single-value bar.
    private var accessibilityValue: String {
        segments.map { segment in
            let fraction = min(1, max(0, segment.fraction.isFinite ? segment.fraction : 0))
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return segment.label.map { "\($0) \(percent)" } ?? percent
        }
        .joined(separator: ", ")
    }
}

/// Segmented 20pt bar (memory used / cache / free).
public struct SplitBar: View {
    let parts: [(value: Double, color: Color)]

    public init(_ parts: [(value: Double, color: Color)]) {
        self.parts = parts
    }

    public var body: some View {
        let values = parts.map { max(0, $0.value.isFinite ? $0.value : 0) }
        StackedBar(
            parts: zip(values, parts).map { ($0, $1.color) },
            domain: max(values.reduce(0, +), 0.0001),
            cornerRadius: RX.Radius.sm
        )
        .frame(height: 20)
        .animation(.easeOut(duration: 0.3), value: values)
    }
}

/// One horizontal bar of adjacent parts, laid end to end from zero over
/// `0...domain`, with a hairline gap between parts.
private struct StackedBar: View {
    struct Part: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let color: Color
    }

    let parts: [Part]
    let domain: Double
    let cornerRadius: CGFloat

    init(parts: [(value: Double, color: Color)], domain: Double, cornerRadius: CGFloat) {
        var start = 0.0
        var laid: [Part] = []
        // Part of the domain left as a gap between parts; tiny parts drop.
        let gap = domain * 0.006
        for (index, part) in parts.enumerated() {
            let end = start + part.value
            if end - start > gap * 2 {
                laid.append(Part(id: index, start: start, end: end - gap, color: part.color))
            }
            start = end
        }
        self.parts = laid
        self.domain = domain
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Chart(parts) { part in
            BarMark(
                xStart: .value("Start", part.start),
                xEnd: .value("End", part.end)
            )
            .foregroundStyle(part.color)
            .cornerRadius(cornerRadius)
        }
        .chartXScale(domain: 0 ... domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

/// Legend entry: swatch, name, bold value.
public struct LegendItem: View {
    let title: String
    let value: String
    let color: Color
    let outlined: Bool

    public init(_ title: String, value: String, color: Color, outlined: Bool = false) {
        self.title = title
        self.value = value
        self.color = color
        self.outlined = outlined
    }

    public var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(outlined ? Color.rxControlBorder : .clear, lineWidth: 1)
                )
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.rxInkSecondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.rxInk)
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}

/// 2pt line with a soft area fill, no points, no axes.
public struct Sparkline: View {
    let values: [Double]
    let maxValue: Double?
    let color: Color
    let fill: Color

    public init(_ values: [Double], maxValue: Double? = nil, color: Color = .rxAccent, fill: Color = .rxAccentFill) {
        self.values = values
        self.maxValue = maxValue
        self.color = color
        self.fill = fill
    }

    public var body: some View {
        // Headroom above the peak unless the caller fixed the scale.
        let top = max(maxValue ?? (values.max() ?? 1) * 1.15, 0.0001)
        Chart {
            if values.count > 1 {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("Sample", index), y: .value("Value", min(value, top)))
                        .foregroundStyle(fill)
                    LineMark(x: .value("Sample", index), y: .value("Value", min(value, top)))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .chartXScale(domain: 0 ... max(1, values.count - 1))
        .chartYScale(domain: 0 ... top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .animation(.easeOut(duration: 0.3), value: values)
        .accessibilityHidden(true)
    }
}

/// A per-core tile: index top-left, percent top-right, fill height = usage.
public struct CoreTile: View {
    let index: Int
    let percent: Double
    let height: CGFloat

    public init(index: Int, percent: Double, height: CGFloat = 44) {
        self.index = index
        self.percent = percent
        self.height = height
    }

    public var body: some View {
        let fraction = max(0, min(1, percent / 100))
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.rxSurfaceSunken)
            Rectangle()
                .fill(rxUsageColor(percent).opacity(0.85))
                .frame(height: height * CGFloat(fraction))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .top) {
            HStack {
                Text("\(index)")
                Spacer(minLength: 0)
                Text(RXFormat.percent(percent))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(fraction > 0.7 ? Color.white : Color.rxInkSecondary)
            .padding(.horizontal, 5)
            .padding(.top, 4)
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: percent)
        .accessibilityElement()
        .accessibilityLabel("Core \(index), \(RXFormat.percent(percent)) percent")
    }
}

/// 4pt `accent` progress bar.
public struct RXProgressBar: View {
    let fraction: Double
    public init(_ fraction: Double) { self.fraction = fraction }
    public var body: some View {
        ProgressView(value: min(1, max(0, fraction.isFinite ? fraction : 0)))
            .progressViewStyle(.linear)
            .tint(.rxAccent)
    }
}
