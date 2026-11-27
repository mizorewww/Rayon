//
//  LiveEndpointTests.swift
//  TelemetryTests
//
//  Posts the sample reports with the app's own sender to a running Worker:
//  TELEMETRY_LIVE_ENDPOINT=http://127.0.0.1:8787/v1/reports swift test --filter LiveEndpoint
//  (see Server/Telemetry/README.md). With TELEMETRY_LIVE_QUEUE set to an
//  app's Application Support/Telemetry/pending, it sends those real reports
//  instead, as a Release build would (a Debug build marks them "debug",
//  which the Worker refuses). Skipped otherwise.
//

@testable import Telemetry
import XCTest

final class LiveEndpointTests: XCTestCase {
    func testTheWorkerTakesTheSampleReports() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["TELEMETRY_LIVE_ENDPOINT"].flatMap(URL.init(string:)) else {
            throw XCTSkip("TELEMETRY_LIVE_ENDPOINT is not set")
        }
        var reports = [Samples.full, Samples.crashOnly].map { report in
            var report = report
            report.nonce = UUID()
            return report
        }
        if let queue = ProcessInfo.processInfo.environment["TELEMETRY_LIVE_QUEUE"] {
            reports = TelemetryQueue(root: URL(fileURLWithPath: queue).deletingLastPathComponent()).entries().map { entry in
                var report = entry.report
                report.channel = .direct
                return report
            }
            XCTAssertFalse(reports.isEmpty, "no reports in \(queue)")
        }
        let accepted = try await TelemetrySender(endpoint: endpoint).send(Array(reports.prefix(TelemetryCollector.batchSize)))
        XCTAssertTrue(accepted)
    }
}
