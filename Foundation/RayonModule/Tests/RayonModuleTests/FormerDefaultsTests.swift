//
//  FormerDefaultsTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class FormerDefaultsTests: XCTestCase {
    func testSettingsSavedUnderTheFormerNamesAreAdoptedOnce() throws {
        let suite = "me.mizorewww.rayon.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(12, forKey: "wiki.qaq.rayon.timeout")
        defaults.set("dark", forKey: "wiki.qaq.rayon.appearance")
        defaults.set(true, forKey: "wiki.qaq.redirect.diag")
        defaults.set(30, forKey: "me.mizorewww.rayon.monitorInterval")
        defaults.set(5, forKey: "wiki.qaq.rayon.monitorInterval")
        defaults.set(Data([1, 2, 3]), forKey: "machineGroupEncrypted")

        RayonStore.adoptFormerDefaults(in: defaults, domain: suite)
        XCTAssertEqual(defaults.integer(forKey: "me.mizorewww.rayon.timeout"), 12)
        XCTAssertEqual(defaults.string(forKey: "me.mizorewww.rayon.appearance"), "dark")
        XCTAssertTrue(defaults.bool(forKey: "me.mizorewww.redirect.diag"))
        XCTAssertEqual(defaults.integer(forKey: "me.mizorewww.rayon.monitorInterval"), 30, "a value already saved stands")
        XCTAssertEqual(defaults.integer(forKey: "wiki.qaq.rayon.timeout"), 12, "the former names are left alone")
        XCTAssertEqual(defaults.data(forKey: "machineGroupEncrypted"), Data([1, 2, 3]))

        // Once only: a setting removed later is not brought back.
        defaults.removeObject(forKey: "me.mizorewww.rayon.timeout")
        RayonStore.adoptFormerDefaults(in: defaults, domain: suite)
        XCTAssertNil(defaults.object(forKey: "me.mizorewww.rayon.timeout"))
    }
}
