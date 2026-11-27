//
//  AppSettingsSync.swift
//  RayonModule
//
//  Keeps the app settings record and the settings here in step: a change
//  made here is written to the record (and so queued for iCloud), and a
//  record from another device is set here, through ConfigurableKit, so
//  whatever shows or applies a setting hears of it.
//

import Combine
import ConfigurableKit
import Foundation

@MainActor
final class AppSettingsSync {
    /// The settings that travel: those `AppSettings` declares `.synced`.
    let keys: Set<String>

    private let storage: KeyValueStorage
    private let record: SettingsRecordSync<RDAppSettings>
    private var subscriptions: Set<AnyCancellable> = []
    private var observer: (any NSObjectProtocol)?

    init(
        storage: RayonStorage,
        settings: KeyValueStorage = ConfigurableKit.storage,
        keys: Set<String> = AppSettings.syncedKeys
    ) {
        self.storage = settings
        self.keys = keys
        record = SettingsRecordSync(storage: storage, syncs: keys.contains, read: {
            Self.entries(in: settings, keys: keys)
        }) { values in
            Self.set(values, in: settings, keys: keys)
        }
    }

    /// A change made here is written to the record as it is made, so the
    /// record is the newer side at launch once it exists. Before, these
    /// settings are written as old, so another device's changes win.
    func start() {
        guard observer == nil else { return }
        if record.record != nil {
            pull()
        } else {
            push(changed: Date(timeIntervalSince1970: 0))
        }
        storage.valueUpdatePublisher
            .filter { [keys] in keys.contains($0.0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.push() }
            }
            .store(in: &subscriptions)
        observer = NotificationCenter.default.addObserver(
            forName: RayonStorage.didMergeRemoteChanges, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
    }

    /// The settings here that travel and are set, as their stored JSON.
    static func entries(in storage: KeyValueStorage, keys: Set<String>) -> [String: RDAppSettings.Value] {
        var entries: [String: RDAppSettings.Value] = [:]
        for key in keys {
            guard let data = storage.value(forKey: key),
                  let value = try? JSONDecoder().decode(RDAppSettings.Value.self, from: data)
            else { continue }
            entries[key] = value
        }
        return entries
    }

    /// Writes what changed here to the record.
    func push(changed: Date? = nil) {
        record.push(changed: changed)
    }

    /// Sets the record's settings here.
    func pull() {
        record.pull()
    }

    /// Sets `values` here; a setting they do not have is reset.
    private static func set(_ values: [String: RDAppSettings.Value], in storage: KeyValueStorage, keys: Set<String>) {
        for key in keys {
            let data = values[key].flatMap { try? JSONEncoder().encode($0) }
            guard data != storage.value(forKey: key) else { continue }
            storage.setValue(data, forKey: key)
        }
    }
}
