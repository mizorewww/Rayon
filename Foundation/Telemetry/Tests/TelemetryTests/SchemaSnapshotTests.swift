//
//  SchemaSnapshotTests.swift
//  TelemetryTests
//
//  The report's shape is pinned: a field or enum case added to the report
//  fails here until Fixtures/ is updated, which makes it a reviewed change
//  (docs/telemetry.md §4.2). Server/Telemetry's tests post the same sample.
//  Run with TELEMETRY_RECORD_SNAPSHOT=1 to rewrite the fixtures.
//

@testable import Telemetry
import XCTest

final class SchemaSnapshotTests: XCTestCase {
    func testTheSampleReportMatchesTheSnapshot() throws {
        try assertSnapshot(TelemetryQueue.prettyEncoder().encode([Samples.full, Samples.crashOnly]), named: "report-sample.json")
    }

    func testTheEnumCasesMatchTheSnapshot() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try assertSnapshot(encoder.encode(Samples.enumCases), named: "report-enums.json")
    }

    func testTheSampleDecodesBackToItself() throws {
        let data = try TelemetryQueue.encoder().encode(Samples.full)
        XCTAssertEqual(try JSONDecoder().decode(TelemetryReport.self, from: data), Samples.full)
    }

    private func assertSnapshot(_ data: Data, named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
        if ProcessInfo.processInfo.environment["TELEMETRY_RECORD_SNAPSHOT"] != nil {
            try (data + Data("\n".utf8)).write(to: fixture)
            return
        }
        let expected = try String(contentsOf: fixture, encoding: .utf8).trimmingCharacters(in: .newlines)
        let actual = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(actual, expected, "The report schema changed. Review it against docs/telemetry.md, then record with TELEMETRY_RECORD_SNAPSHOT=1.", file: file, line: line)
    }
}

enum Samples {
    static let environment = TelemetryEnvironment(
        appVersion: .init(major: 5, minor: 2, patch: 0), channel: .appStore, platform: .macOS,
        osVersion: .init(major: 15, minor: 4), deviceClass: .macAppleSilicon, language: .en, region: .other
    )

    static let diagnostic = TelemetryReport.Diagnostic(
        kind: .crash,
        appVersion: .init(major: 5, minor: 2, patch: 0),
        osVersion: .init(major: 15, minor: 4),
        exceptionType: 1,
        exceptionCode: 0,
        signal: 11,
        terminationReason: .signal,
        objcExceptionName: .NSInvalidArgumentException,
        objcExceptionClass: .NSException,
        hangDuration: .under3s,
        callStacks: [
            .init(threadAttributed: true, frames: [
                .init(origin: .app, binaryUUID: UUID(uuidString: "70B89F27-1634-3580-A695-57CDB41D7743"), offset: 165_304, sampleCount: 1, subFrames: [
                    .init(origin: .system, binaryUUID: UUID(uuidString: "9156BE86-F2A8-3E54-B5C5-4AB0FA1D0BCB"), offset: 4_242, sampleCount: 1, subFrames: [
                        .init(origin: .other, binaryUUID: nil, offset: nil, sampleCount: 1, subFrames: []),
                    ]),
                ]),
            ]),
        ]
    )

    static var full: TelemetryReport {
        var report = TelemetryReport(level: .detailed, environment: environment)
        report.nonce = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        report.diagnostics = [diagnostic]
        report.usage = .init(
            counts: .bucketed([.terminalSessionsOpened: 7, .sftpBrowsed: 1, .editorOpened: 3]),
            portForwardsStarted: .bucketed([.local: 2]),
            connectionOutcome: .bucketed([.success: 9, .authFailed: 1]),
            authMethodUsed: .flags([.publicKey]),
            keyTypes: .flags([.ed25519, .rsa]),
            savedHosts: CountBucket(12),
            identities: CountBucket(3),
            iCloudSyncEnabled: true,
            customTheme: false,
            redactionMode: .address,
            activeDaysLast28: CountBucket(14)
        )
        report.detail = .init(
            connectLatency: .bucketed([.under300ms: 6, .under1s: 3]),
            remoteOSFamily: .bucketed([.linux: 5, .darwin: 1]),
            metrics: .init(launchMilliseconds: 420, hangMilliseconds: 1500, peakMemoryMegabytes: 380, cpuSeconds: 75, diskWriteMegabytes: 12)
        )
        return report
    }

    static var crashOnly: TelemetryReport {
        var report = TelemetryReport(level: .crashReports, environment: environment)
        report.nonce = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        report.diagnostics = [diagnostic]
        return report
    }

    static var enumCases: [String: [String]] {
        func names<E: CaseIterable & RawRepresentable>(_: E.Type) -> [String] { E.allCases.map { "\($0.rawValue)" } }
        return [
            "level": names(TelemetryLevel.self),
            "countBucket": names(CountBucket.self),
            "channel": names(TelemetryReport.Channel.self),
            "platform": names(TelemetryReport.Platform.self),
            "deviceClass": names(TelemetryReport.DeviceClass.self),
            "language": names(TelemetryReport.Language.self),
            "regionGroup": names(TelemetryReport.RegionGroup.self),
            "feature": names(TelemetryReport.Feature.self),
            "portForwardKind": names(TelemetryReport.PortForwardKind.self),
            "connectionOutcome": names(TelemetryReport.ConnectionOutcome.self),
            "authMethod": names(TelemetryReport.AuthMethod.self),
            "keyType": names(TelemetryReport.KeyType.self),
            "redactionMode": names(TelemetryReport.RedactionMode.self),
            "latencyBucket": names(TelemetryReport.LatencyBucket.self),
            "remoteOSFamily": names(TelemetryReport.RemoteOSFamily.self),
            "diagnosticKind": names(TelemetryReport.Diagnostic.Kind.self),
            "terminationReason": names(TelemetryReport.Diagnostic.TerminationReason.self),
            "objcExceptionName": names(TelemetryReport.Diagnostic.ObjCExceptionName.self),
            "objcExceptionClass": names(TelemetryReport.Diagnostic.ObjCExceptionClass.self),
            "hangDuration": names(TelemetryReport.Diagnostic.HangDuration.self),
            "frameOrigin": names(TelemetryReport.Frame.Origin.self),
            "millisecondSteps": TelemetryReport.Metrics.millisecondSteps.map(String.init),
            "megabyteSteps": TelemetryReport.Metrics.megabyteSteps.map(String.init),
            "secondSteps": TelemetryReport.Metrics.secondSteps.map(String.init),
        ]
    }
}
