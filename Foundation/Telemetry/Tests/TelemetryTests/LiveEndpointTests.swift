//
//  LiveEndpointTests.swift
//  TelemetryTests
//
//  Posts the sample reports with the app's own sender to a running Worker:
//  TELEMETRY_LIVE_ENDPOINT=http://127.0.0.1:8787/v1/reports swift test --filter LiveEndpoint
//  (see Server/Telemetry/README.md). Skipped otherwise.
//

@testable import Telemetry
import XCTest

final class LiveEndpointTests: XCTestCase {
    func testTheWorkerTakesTheSampleReports() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["TELEMETRY_LIVE_ENDPOINT"].flatMap(URL.init(string:)) else {
            throw XCTSkip("TELEMETRY_LIVE_ENDPOINT is not set")
        }
        var full = Samples.full
        full.nonce = UUID()
        var crash = Samples.crashOnly
        crash.nonce = UUID()
        let accepted = try await TelemetrySender(endpoint: endpoint).send([full, crash])
        XCTAssertTrue(accepted)
    }
}
