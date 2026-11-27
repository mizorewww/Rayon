//
//  TelemetrySubscriber.swift
//  Telemetry
//
//  MetricKit's deliveries: diagnostics (level 1) are scrubbed into a report
//  of their own; daily metrics (level 3) are kept for the day's report.
//

import Foundation
import MetricKit

final class TelemetrySubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    let scrubber = DiagnosticScrubber()
    let diagnostics: @Sendable ([TelemetryReport.Diagnostic]) -> Void
    let metrics: @Sendable (TelemetryReport.Metrics) -> Void

    init(diagnostics: @escaping @Sendable ([TelemetryReport.Diagnostic]) -> Void, metrics: @escaping @Sendable (TelemetryReport.Metrics) -> Void) {
        self.diagnostics = diagnostics
        self.metrics = metrics
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let items = payloads.flatMap { scrubber.diagnostics(fromPayload: $0.jsonRepresentation()) }
        diagnostics(items)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard let payload = payloads.last else { return }
        metrics(TelemetryReport.Metrics(
            launchMilliseconds: payload.applicationLaunchMetrics.flatMap { Self.median($0.histogrammedTimeToFirstDraw) },
            hangMilliseconds: payload.applicationResponsivenessMetrics.map { Self.total($0.histogrammedApplicationHangTime) },
            peakMemoryMegabytes: payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value,
            cpuSeconds: payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value,
            diskWriteMegabytes: payload.diskIOMetrics?.cumulativeLogicalWrites.converted(to: .megabytes).value
        ))
    }

    private static func buckets(_ histogram: MXHistogram<UnitDuration>) -> [(milliseconds: Double, count: Int)] {
        histogram.bucketEnumerator.compactMap { $0 as? MXHistogramBucket<UnitDuration> }.map {
            ($0.bucketStart.converted(to: .milliseconds).value, $0.bucketCount)
        }
    }

    /// The start of the bucket that holds the middle sample.
    static func median(_ histogram: MXHistogram<UnitDuration>) -> Double? {
        let buckets = buckets(histogram)
        var remaining = buckets.reduce(0) { $0 + $1.count } / 2
        for bucket in buckets {
            remaining -= bucket.count
            if remaining < 0 { return bucket.milliseconds }
        }
        return buckets.last?.milliseconds
    }

    static func total(_ histogram: MXHistogram<UnitDuration>) -> Double {
        buckets(histogram).reduce(0) { $0 + $1.milliseconds * Double($1.count) }
    }
}
