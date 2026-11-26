@testable import RayonModule
import XCTest

final class SecretStoreTests: XCTestCase {
    private let store = SecretStore(service: "me.mizorewww.rayon.tests.\(UUID().uuidString)")

    override func tearDown() {
        try? store.removeAll()
        super.tearDown()
    }

    func testWritesReplacesAndRemoves() throws {
        XCTAssertNil(try store.data(for: "a"))
        try store.set(Data("one".utf8), for: "a")
        XCTAssertEqual(try store.data(for: "a"), Data("one".utf8))
        try store.set(Data("two".utf8), for: "a")
        XCTAssertEqual(try store.data(for: "a"), Data("two".utf8))
        try store.set(nil, for: "a")
        XCTAssertNil(try store.data(for: "a"))
    }

    func testCodableValues() throws {
        try store.setValue(["password": "hunter2"], for: "b")
        XCTAssertEqual(try store.value([String: String].self, for: "b"), ["password": "hunter2"])
        try store.removeAll()
        XCTAssertNil(try store.value([String: String].self, for: "b"))
    }
}
