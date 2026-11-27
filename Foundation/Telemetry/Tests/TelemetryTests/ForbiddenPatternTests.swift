//
//  ForbiddenPatternTests.swift
//  TelemetryTests
//
//  docs/telemetry.md §4.2 "Forbidden, at every level": random reports, and
//  MetricKit payloads stuffed with hosts, users, paths and secrets, are
//  encoded and searched for anything that could be one.
//

@testable import Telemetry
import XCTest

final class ForbiddenPatternTests: XCTestCase {
    /// What a string in a report may look like: an enum's raw value, a
    /// version, a UUID. Nothing else is a string at all.
    static let allowedString = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9-]{0,40}|\d{1,3}\.\d{1,3}(\.\d{1,3})?|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$"#)

    static let forbidden: [(String, NSRegularExpression)] = [
        ("IPv4 address", #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#),
        ("IPv6 address", #"[0-9a-fA-F]{1,4}::?[0-9a-fA-F]{1,4}:"#),
        ("host name", #"[A-Za-z0-9-]+\.(com|net|org|io|dev|local|lan|internal|cn|de)\b"#),
        ("user@host", #"[A-Za-z0-9._-]+@[A-Za-z0-9.-]+"#),
        ("path", #"(/Users/|/home/|/private/|/var/|~/|\\\\)"#),
        ("host:port", #"[A-Za-z0-9.-]+:\d{2,5}\b"#),
        ("key material", #"(ssh-(rsa|ed25519)|ecdsa-sha2|BEGIN [A-Z ]*PRIVATE KEY|SHA256:[A-Za-z0-9+/]{20,})"#),
        ("shell command", #"\b(sudo|rm -rf|cat |ls -|export [A-Z_]+=)"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    func testRandomReportsCarryOnlyAllowedStrings() throws {
        var generator = SeededGenerator(seed: 0x5241_594F_4E)
        for _ in 0 ..< 500 {
            let report = Self.randomReport(using: &generator)
            let data = try TelemetryQueue.encoder().encode(report)
            try assertClean(data)
        }
    }

    func testScrubbedPayloadsCarryNoneOfTheirStrings() throws {
        var generator = SeededGenerator(seed: 42)
        let scrubber = DiagnosticScrubber { name, _ in name == "Rayon" ? .app : name == "UIKitCore" ? .system : .other }
        for _ in 0 ..< 200 {
            let secret = Self.secrets.randomElement(using: &generator)!
            let payload = ScrubberTests.payload(secret: secret, extraKey: "k\(generator.next() % 1000)")
            var report = TelemetryReport(level: .crashReports, environment: Samples.environment)
            report.diagnostics = scrubber.diagnostics(fromPayload: payload)
            XCTAssertFalse(report.diagnostics.isEmpty)
            let data = try TelemetryQueue.encoder().encode(report)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(secret), "\(secret) survived scrubbing")
            try assertClean(data)
        }
    }

    static let secrets = [
        "root@prod-db-01.example.com", "10.0.12.7", "fe80::1ff:fe23:4567:890a", "/Users/alice/.ssh/id_ed25519",
        "deploy.internal:2222", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
        "SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8", "sudo rm -rf /var/www", "hunter2-password",
        "-----BEGIN OPENSSH PRIVATE KEY-----", "My Secret Server", "/home/bob/projects/client.tar.gz",
    ]

    private func assertClean(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = String(decoding: data, as: UTF8.self)
        for (name, pattern) in Self.forbidden where pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            XCTFail("a report contains a \(name): \(text)", file: file, line: line)
        }
        for string in Self.strings(in: try JSONSerialization.jsonObject(with: data)) {
            let range = NSRange(string.startIndex..., in: string)
            XCTAssertNotNil(Self.allowedString.firstMatch(in: string, range: range), "free string \"\(string)\" in a report", file: file, line: line)
        }
    }

    /// Every string value and key in a JSON value.
    static func strings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap { strings(in: $0) }
        case let object as [String: Any]: object.flatMap { [$0.key] + strings(in: $0.value) }
        default: []
        }
    }

    static func randomReport(using generator: inout SeededGenerator) -> TelemetryReport {
        func pick<E: CaseIterable>(_: E.Type) -> E { E.allCases.randomElement(using: &generator)! }
        func count() -> Int { Int.random(in: 0 ... 500, using: &generator) }
        let environment = TelemetryEnvironment(
            appVersion: .init(major: count(), minor: count(), patch: count()), channel: pick(TelemetryReport.Channel.self),
            platform: pick(TelemetryReport.Platform.self), osVersion: .init(major: count(), minor: count()),
            deviceClass: pick(TelemetryReport.DeviceClass.self), language: pick(TelemetryReport.Language.self),
            region: [.strict, .china, .other].randomElement(using: &generator)!
        )
        var report = TelemetryReport(level: pick(TelemetryLevel.self), environment: environment)
        report.usage = .init(
            counts: .bucketed(Dictionary(uniqueKeysWithValues: TelemetryReport.Feature.allCases.map { ($0, count()) })),
            portForwardsStarted: .bucketed([pick(TelemetryReport.PortForwardKind.self): count()]),
            connectionOutcome: .bucketed([pick(TelemetryReport.ConnectionOutcome.self): count()]),
            authMethodUsed: .flags([pick(TelemetryReport.AuthMethod.self)]),
            keyTypes: .flags([pick(TelemetryReport.KeyType.self)]),
            savedHosts: CountBucket(count()), identities: CountBucket(count()),
            iCloudSyncEnabled: Bool.random(using: &generator), customTheme: Bool.random(using: &generator),
            redactionMode: pick(TelemetryReport.RedactionMode.self), activeDaysLast28: CountBucket(count())
        )
        report.detail = .init(
            connectLatency: .bucketed([.init(.milliseconds(count() * 10)): count()]),
            remoteOSFamily: .bucketed([pick(TelemetryReport.RemoteOSFamily.self): count()]),
            metrics: .init(
                launchMilliseconds: Double(count() * 13), hangMilliseconds: Double(count() * 97),
                peakMemoryMegabytes: Double(count() * 7), cpuSeconds: Double(count() * 11), diskWriteMegabytes: Double(count() * 19)
            )
        )
        report.diagnostics = [Samples.diagnostic]
        return report
    }
}

/// SplitMix64, so a failing case can be replayed.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
