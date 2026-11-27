//
//  ScrubberTests.swift
//  TelemetryTests
//
//  Crafted MXDiagnosticPayload JSON, in the shape Xcode's "Simulate
//  MetricKit Payloads" delivers, with user strings in every free field.
//

@testable import Telemetry
import XCTest

final class ScrubberTests: XCTestCase {
    static let appUUID = "70B89F27-1634-3580-A695-57CDB41D7743"
    static let systemUUID = "9156BE86-F2A8-3E54-B5C5-4AB0FA1D0BCB"
    static let pluginUUID = "11111111-2222-3333-4444-555555555555"

    let scrubber = DiagnosticScrubber { name, uuid in
        if uuid?.uuidString == ScrubberTests.appUUID { return .app }
        if uuid?.uuidString == ScrubberTests.systemUUID { return .system }
        return .other
    }

    static func payload(secret: String, extraKey: String = "unknownKey") -> Data {
        let frame: [String: Any] = [
            "binaryUUID": appUUID, "offsetIntoBinaryTextSegment": 165_304, "sampleCount": 1,
            "binaryName": "Rayon", "address": 4_301_234_567,
            "subFrames": [[
                "binaryUUID": systemUUID, "offsetIntoBinaryTextSegment": 4242, "sampleCount": 1,
                "binaryName": "libsystem_kernel.dylib", "address": 6_442_450_944,
                "subFrames": [[
                    "binaryUUID": pluginUUID, "offsetIntoBinaryTextSegment": 77, "sampleCount": 1,
                    "binaryName": secret, "address": 1,
                ]],
            ]],
        ]
        let meta: [String: Any] = [
            "appVersion": "5.2.0", "appBuildVersion": "512", "osVersion": "macOS 15.4.1 (24E263)",
            "deviceType": "Mac15,6", "platformArchitecture": "arm64e", "regionFormat": "DE",
            "bundleIdentifier": "me.mizorewww.rayon", "isTestFlightApp": false, "lowPowerModeEnabled": false, "pid": 4711,
            "exceptionType": 1, "exceptionCode": 0, "signal": 11,
            "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11 \(secret)",
            "virtualMemoryRegionInfo": "0 is not in any region. \(secret)",
            "objectiveCexceptionReason": [
                "composedMessage": "Could not connect to \(secret)",
                "formatString": "Could not connect to %@",
                "arguments": [secret],
                "exceptionType": "NSException",
                "className": "NSException",
                "exceptionName": "NSInvalidArgumentException",
            ],
            "hangDuration": "2.5 sec",
            extraKey: secret,
        ]
        let crash: [String: Any] = [
            "version": "1.0.0",
            "callStackTree": [
                "callStackPerThread": true,
                "callStacks": [
                    ["threadAttributed": true, "callStackRootFrames": [frame]],
                    ["threadAttributed": false, "callStackRootFrames": [frame]],
                ],
            ],
            "diagnosticMetaData": meta,
        ]
        var hangMeta = meta
        hangMeta["objectiveCexceptionReason"] = ["exceptionName": secret, "className": secret]
        let payload: [String: Any] = [
            "timeStampBegin": "2026-11-27 09:00:00", "timeStampEnd": "2026-11-27 10:00:00",
            "crashDiagnostics": [crash],
            "hangDiagnostics": [["callStackTree": ["callStacks": [["threadAttributed": true, "callStackRootFrames": [frame]]]], "diagnosticMetaData": hangMeta]],
            "cpuExceptionDiagnostics": [["diagnosticMetaData": ["totalCPUTime": "20 sec", "totalSampledTime": secret]]],
            "diskWriteExceptionDiagnostics": [["diagnosticMetaData": ["writesCaused": secret]]],
            "appLaunchDiagnostics": [["diagnosticMetaData": ["launchDuration": secret]]],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    func testACrashKeepsOnlyNumbersEnumsAndItsOwnStack() throws {
        let items = scrubber.diagnostics(fromPayload: Self.payload(secret: "root@db.example.com"))
        XCTAssertEqual(items.map(\.kind), [.crash, .hang, .cpuException, .diskWriteException])
        let crash = items[0]
        XCTAssertEqual(crash.appVersion?.description, "5.2.0")
        XCTAssertEqual(crash.osVersion?.description, "15.4")
        XCTAssertEqual(crash.exceptionType, 1)
        XCTAssertEqual(crash.exceptionCode, 0)
        XCTAssertEqual(crash.signal, 11)
        XCTAssertEqual(crash.terminationReason, .signal)
        XCTAssertEqual(crash.objcExceptionName, .NSInvalidArgumentException)
        XCTAssertEqual(crash.objcExceptionClass, .NSException)
        // Only the crashed thread.
        XCTAssertEqual(crash.callStacks.count, 1)
        let root = try XCTUnwrap(crash.callStacks.first?.frames.first)
        XCTAssertEqual(root.origin, .app)
        XCTAssertEqual(root.binaryUUID?.uuidString, Self.appUUID)
        XCTAssertEqual(root.offset, 165_304)
        let system = try XCTUnwrap(root.subFrames.first)
        XCTAssertEqual(system.origin, .system)
        XCTAssertEqual(system.offset, 4242)
        // A binary that is neither ours nor the system's keeps its place, not its identity.
        let plugin = try XCTUnwrap(system.subFrames.first)
        XCTAssertEqual(plugin, .init(origin: .other, binaryUUID: nil, offset: nil, sampleCount: 1, subFrames: []))
    }

    func testFreeStringsAreGone() throws {
        let secret = "Could-Not-Reach-prod.example.com"
        var report = TelemetryReport(level: .crashReports, environment: Samples.environment)
        report.diagnostics = scrubber.diagnostics(fromPayload: Self.payload(secret: secret))
        let text = String(decoding: try TelemetryQueue.encoder().encode(report), as: UTF8.self)
        for word in [secret, "composedMessage", "arguments", "formatString", "virtualMemoryRegionInfo", "binaryName", "address",
                     "Segmentation", "regionFormat", "deviceType", "Mac15", "bundleIdentifier", "timeStamp", "pid", "512"]
        {
            XCTAssertFalse(text.contains(word), "\(word) reached the report")
        }
    }

    func testAnExceptionNameOutsideTheAllowListIsDropped() {
        let hang = scrubber.diagnostics(fromPayload: Self.payload(secret: "MyAppSecretException"))[1]
        XCTAssertEqual(hang.kind, .hang)
        XCTAssertNil(hang.objcExceptionName)
        XCTAssertNil(hang.objcExceptionClass)
        XCTAssertEqual(hang.hangDuration, .under3s)
    }

    func testTerminationReasonsMapToTheirNamespace() {
        XCTAssertEqual(DiagnosticScrubber.terminationReason("Namespace SPRINGBOARD, Code 0x8badf00d"), .watchdog)
        XCTAssertEqual(DiagnosticScrubber.terminationReason("Namespace CODESIGNING, Code 2 Invalid Page"), .codeSigning)
        XCTAssertEqual(DiagnosticScrubber.terminationReason("Namespace JETSAM, Code 0"), .jetsam)
        XCTAssertEqual(DiagnosticScrubber.terminationReason("something new from host.example.com"), .other)
    }

    func testDurationsParse() {
        XCTAssertEqual(DiagnosticScrubber.seconds("20 sec"), 20)
        XCTAssertEqual(DiagnosticScrubber.seconds("1,500 ms"), 1.5)
        XCTAssertEqual(DiagnosticScrubber.seconds("2 min"), 120)
        XCTAssertNil(DiagnosticScrubber.seconds("forever"))
    }

    func testAHugeTreeIsCut() {
        let leaf: [String: Any] = ["binaryUUID": Self.appUUID, "offsetIntoBinaryTextSegment": 1, "sampleCount": 1]
        let frame: [String: Any] = ["binaryUUID": Self.appUUID, "offsetIntoBinaryTextSegment": 1, "sampleCount": 1, "subFrames": Array(repeating: leaf, count: 400)]
        let payload: [String: Any] = ["hangDiagnostics": [["callStackTree": ["callStacks": [["threadAttributed": true, "callStackRootFrames": [frame, frame]]]]]]]
        let items = scrubber.diagnostics(fromPayload: try! JSONSerialization.data(withJSONObject: payload))
        func count(_ frames: [TelemetryReport.Frame]) -> Int { frames.reduce(0) { $0 + 1 + count($1.subFrames) } }
        XCTAssertEqual(count(items[0].callStacks[0].frames), DiagnosticScrubber.frameLimit)
    }

    func testNotJSONGivesNothing() {
        XCTAssertEqual(scrubber.diagnostics(fromPayload: Data("nope".utf8)), [])
    }
}
