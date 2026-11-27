//
//  CollectorTests.swift
//  TelemetryTests
//

import Synchronization
@testable import Telemetry
import XCTest

final class CollectorTests: XCTestCase {
    private var root: URL!
    private let clock = Clock()

    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var date: Date {
            get { value.withLock { $0 } }
            set { value.withLock { $0 = newValue } }
        }
    }

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: "TelemetryTests-\(UUID().uuidString)")
        StubProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func collector(level: TelemetryLevel, detailed: Bool = false) async -> TelemetryCollector {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let collector = TelemetryCollector(
            root: root,
            sender: TelemetrySender(endpoint: URL(string: "https://telemetry.test/v1/reports")!, configuration: configuration),
            now: { [clock] in clock.date },
            coinFlip: { detailed }
        )
        await collector.configure(environment: Samples.environment, snapshot: .empty, level: level)
        return collector
    }

    private func nextDay() { clock.date += 86400 }

    func testAFinishedDayBecomesOneBucketedReport() async throws {
        let collector = await collector(level: .usage)
        await collector.rollOver(snapshot: TelemetrySnapshot(savedHosts: 7, identities: 1, keyTypes: [.ed25519], iCloudSyncEnabled: true, customTheme: false, redactionMode: .none))
        for _ in 0 ..< 3 { await collector.record(.feature(.terminalSessionsOpened)) }
        await collector.record(.connection(.success, auth: .publicKey))
        await collector.record(.connection(.timeout, auth: nil))
        await collector.record(.portForwardStarted(.dynamic))
        await collector.record(.connectLatency(.milliseconds(80)))
        let before = await collector.pending()
        XCTAssertEqual(before.count, 0)

        nextDay()
        await collector.rollOver(snapshot: .empty)
        let reports = await collector.pending()
        XCTAssertEqual(reports.count, 1)
        let usage = try XCTUnwrap(reports.first?.usage)
        XCTAssertEqual(usage.counts[.terminalSessionsOpened], .few)
        XCTAssertEqual(usage.counts[.editorOpened], .zero)
        XCTAssertEqual(usage.connectionOutcome[.success], .one)
        XCTAssertEqual(usage.connectionOutcome[.timeout], .one)
        XCTAssertEqual(usage.portForwardsStarted[.dynamic], .one)
        XCTAssertEqual(usage.authMethodUsed[.publicKey], true)
        XCTAssertEqual(usage.authMethodUsed[.password], false)
        XCTAssertEqual(usage.savedHosts, .some)
        XCTAssertEqual(usage.keyTypes[.ed25519], true)
        XCTAssertEqual(usage.activeDaysLast28, .one)
        XCTAssertNil(reports.first?.detail, "level 2 sends no detail")
    }

    func testLevelThreeAddsDetailOnlyOnSampledDays() async throws {
        let sampled = await collector(level: .detailed, detailed: true)
        await sampled.rollOver(snapshot: .empty)
        await sampled.record(.connectLatency(.milliseconds(450)))
        await sampled.record(.remoteOS(.linux))
        nextDay()
        await sampled.rollOver(snapshot: .empty)
        let detail = await sampled.pending().first?.detail
        XCTAssertEqual(detail?.connectLatency[.under1s], .one)
        XCTAssertEqual(detail?.remoteOSFamily[.linux], .one)

        try? FileManager.default.removeItem(at: root)
        let unsampled = await collector(level: .detailed, detailed: false)
        await unsampled.rollOver(snapshot: .empty)
        await unsampled.record(.connectLatency(.milliseconds(450)))
        nextDay()
        await unsampled.rollOver(snapshot: .empty)
        let report = await unsampled.pending().first
        XCTAssertNotNil(report?.usage)
        XCTAssertNil(report?.detail)
    }

    func testLevelOneCountsNothing() async {
        let collector = await collector(level: .crashReports)
        await collector.rollOver(snapshot: .empty)
        await collector.record(.feature(.sftpBrowsed))
        nextDay()
        await collector.rollOver(snapshot: .empty)
        let pending = await collector.pending()
        XCTAssertEqual(pending.count, 0)
        await collector.recordDiagnostics([Samples.diagnostic])
        let crashes = await collector.pending()
        XCTAssertEqual(crashes.map(\.level), [.crashReports])
        XCTAssertNil(crashes.first?.usage)
    }

    func testLoweringDropsWhatTheNewLevelWouldNotSend() async {
        let collector = await collector(level: .detailed, detailed: true)
        await collector.rollOver(snapshot: .empty)
        await collector.recordDiagnostics([Samples.diagnostic])
        nextDay()
        await collector.rollOver(snapshot: .empty)
        let levels = await collector.pending().map(\.level)
        XCTAssertEqual(levels, [.detailed, .detailed])

        await collector.setLevel(.crashReports)
        let kept = await collector.pending()
        XCTAssertEqual(kept.count, 0, "reports made at level 3 go")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "today.json").path))

        await collector.setLevel(.off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "pending").path))
        await collector.recordDiagnostics([Samples.diagnostic])
        let none = await collector.pending()
        XCTAssertEqual(none.count, 0)
    }

    func testTheQueueKeepsTheNewestFourteen() async {
        let collector = await collector(level: .crashReports)
        for _ in 0 ..< 20 {
            await collector.recordDiagnostics([Samples.diagnostic])
            try? await Task.sleep(for: .milliseconds(2))
        }
        let count = await collector.pending().count
        XCTAssertEqual(count, TelemetryQueue.capacity)
    }

    func testFlushSendsTenPerRequestAndKeepsTheLastSent() async throws {
        let collector = await collector(level: .crashReports)
        for _ in 0 ..< 13 {
            await collector.recordDiagnostics([Samples.diagnostic])
            try? await Task.sleep(for: .milliseconds(2))
        }
        await collector.flush(allowed: false)
        XCTAssertEqual(StubProtocol.bodies.count, 0, "nothing goes out while sending is not allowed")

        await collector.flush(allowed: true)
        let batches = try StubProtocol.bodies.map { try JSONSerialization.jsonObject(with: $0) as! [String: [Any]] }
        XCTAssertEqual(batches.map { $0["reports"]!.count }, [10, 3])
        let pending = await collector.pending()
        XCTAssertEqual(pending.count, 0)
        let last = await collector.lastSent()
        XCTAssertNotNil(last)
    }

    func testAServerErrorKeepsTheQueue() async {
        StubProtocol.status = 503
        let collector = await collector(level: .crashReports)
        await collector.recordDiagnostics([Samples.diagnostic])
        await collector.flush(allowed: true)
        let pending = await collector.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(TelemetrySender.backoff(afterFailures: 1), .seconds(60))
        XCTAssertEqual(TelemetrySender.backoff(afterFailures: 3), .seconds(240))
        XCTAssertEqual(TelemetrySender.backoff(afterFailures: 30), .seconds(6 * 3600))
    }
}

final class StubProtocol: URLProtocol {
    private struct State {
        var bodies: [Data] = []
        var status = 200
    }

    private static let state = Mutex(State())

    static var bodies: [Data] { state.withLock { $0.bodies } }
    static var status: Int {
        get { state.withLock { $0.status } }
        set { state.withLock { $0.status = newValue } }
    }

    static func reset() { state.withLock { $0 = State() } }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.state.withLock { $0.bodies.append(data) }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
