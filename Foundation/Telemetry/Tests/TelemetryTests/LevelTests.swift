//
//  LevelTests.swift
//  TelemetryTests
//

@testable import Telemetry
import XCTest

final class LevelTests: XCTestCase {
    func testTheStorefrontDecidesTheDefault() {
        typealias Region = TelemetryEnvironment.Region
        for code in ["DEU", "de", "GBR", "GB", "CHE", "NOR", "ISL", "LIE", "FRA"] {
            XCTAssertEqual(Region(countryCode: code), .strict, code)
        }
        XCTAssertEqual(Region(countryCode: "CHN"), .china)
        XCTAssertEqual(Region(countryCode: "CN"), .china)
        XCTAssertEqual(Region(countryCode: "USA"), .other)
        XCTAssertEqual(Region(countryCode: "JP"), .other)
        // Unknown is strict.
        XCTAssertEqual(Region(countryCode: nil), .strict)
        XCTAssertEqual(Region(countryCode: "419"), .strict)
        XCTAssertEqual(Region(countryCode: ""), .strict)
    }

    @MainActor func testWithoutAChoiceOnlyOtherRegionsDefaultToUsage() {
        let defaults = UserDefaults(suiteName: "TelemetryTests-\(UUID().uuidString)")!
        let telemetry = Telemetry(defaults: defaults)
        XCTAssertEqual(telemetry.level, .off, "nothing before the region is known")
        XCTAssertFalse(telemetry.showsNotice)
    }

    func testCountsAreBucketed() {
        XCTAssertEqual([0, 1, 2, 5, 6, 20, 21, 100, 101, 9999].map { CountBucket($0).rawValue }, [0, 1, 2, 2, 6, 6, 21, 21, 101, 101])
    }

    func testVersionsAreCutToNumbers() {
        XCTAssertEqual(TelemetryReport.Version(parsing: "5.2", keepPatch: true)?.description, "5.2.0")
        XCTAssertEqual(TelemetryReport.Version(parsing: "15.4.1", keepPatch: false)?.description, "15.4")
        XCTAssertNil(TelemetryReport.Version(parsing: "beta", keepPatch: true))
        XCTAssertEqual(DiagnosticScrubber.osVersion("iPhone OS 18.1 (22B83)")?.description, "18.1")
    }

    func testDebugBuildsSendNothing() {
        XCTAssertFalse(Telemetry.sendingAllowed)
    }
}
