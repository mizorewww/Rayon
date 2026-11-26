//
//  TestStorage.swift
//  RayonModuleTests
//
//  A database and keychain service of its own for each test, removed
//  afterwards, so tests never touch the user's data.
//

@testable import RayonModule
import XCTest

final class TestStorage {
    let directory: URL
    let secrets: SecretStore
    let storage: RayonStorage

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayon-tests-\(UUID().uuidString)", isDirectory: true)
        secrets = SecretStore(service: "me.mizorewww.rayon.tests.\(UUID().uuidString)")
        storage = try RayonStorage(databaseURL: directory.appendingPathComponent("database.db"), secrets: secrets)
    }

    @MainActor
    func store(defaults: UserDefaults? = nil) -> RayonStore {
        RayonStore(storage: storage, defaults: defaults ?? UserDefaults(suiteName: "rayon-tests-\(UUID().uuidString)")!)
    }

    deinit {
        storage.close()
        try? secrets.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
