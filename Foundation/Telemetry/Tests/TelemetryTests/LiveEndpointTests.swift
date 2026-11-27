//
//  LiveEndpointTests.swift
//  TelemetryTests
//
//  Posts one sample report (level 3, one crash) with the app's own sender
//  to a running Worker:
//  TELEMETRY_LIVE_ENDPOINT=http://127.0.0.1:8787/v1/reports swift test --filter LiveEndpoint
//  (see Server/Telemetry/README.md). Its app version, and its crash's, is
//  0.0.0, which no release has, so its rows are easy to find and delete on a live
//  database. With TELEMETRY_LIVE_QUEUE set to an
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
        var sample = Samples.full
        sample.nonce = UUID()
        let unreleased = TelemetryReport.Version(parsing: "0.0.0", keepPatch: true)!
        sample.appVersion = unreleased
        for index in sample.diagnostics.indices {
            sample.diagnostics[index].appVersion = unreleased
        }
        var reports = [sample]
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
