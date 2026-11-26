//
//  AppSettingsSync.swift
//  RayonModule
//
//  Keeps the app settings record and the user defaults in step: a change
//  made here is written to the record (and so queued for iCloud), and a
//  record from another device is applied to the defaults.
//

import Foundation

@MainActor
final class AppSettingsSync {
    /// The settings that travel. The terminal's font size and what belongs
    /// to this device (its windows, menu bar, accounts) stay.
    static let keys: [String] = [
        RayonStore.Key.timeout,
        RayonStore.Key.monitorInterval,
        RayonStore.Key.maxRecentRecordCount,
        RayonStore.Key.openInterfaceAutomatically,
        RayonStore.Key.saveTemporarySession,
        RayonStore.Key.storeRecent,
        RayonStore.Key.reducedViewEffects,
        RayonStore.Key.disableConformation,
        RayonStore.Key.terminalCopyOnSelect,
        RayonStore.Key.terminalClipboardSharing,
        RayonStore.Key.machineRedacted,
        "me.mizorewww.rayon.appearance",
        "me.mizorewww.rayon.editor.wrapsLines",
        "me.mizorewww.rayon.terminfo.install",
    ]

    private let storage: RayonStorage
    private let defaults: UserDefaults
    private let applied: @MainActor () -> Void
    private var observers: [any NSObjectProtocol] = []
    /// Set while the record's settings are being set: each one set is not
    /// a change here.
    private var applying = false

    /// `applied` runs after another device's settings were set.
    init(storage: RayonStorage, defaults: UserDefaults, applied: @escaping @MainActor () -> Void) {
        self.storage = storage
        self.defaults = defaults
        self.applied = applied
    }

    private var record: RDAppSettings? {
        storage.record(RDAppSettings.self, id: RDAppSettings.recordID)
    }

    /// A change made here is written to the record as it is made, so the
    /// record is the newer side at launch once it exists. Before, these
    /// settings are written as old, so another device's changes win.
    func start() {
        guard observers.isEmpty else { return }
        if record != nil {
            pull()
        } else {
            push(changed: Date(timeIntervalSince1970: 0))
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: RayonStorage.didMergeRemoteChanges, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        })
    }

    /// The settings here that travel and are set.
    func entries() -> [String: RDAppSettings.Value] {
        var entries: [String: RDAppSettings.Value] = [:]
        for key in Self.keys {
            switch defaults.object(forKey: key) {
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                entries[key] = .bool(number.boolValue)
            case let number as NSNumber:
                entries[key] = .int(number.intValue)
            case let text as String:
                entries[key] = .string(text)
            default:
                continue
            }
        }
        return entries
    }

    /// Writes what this device has, if it differs from the record.
    func push(changed: Date? = nil) {
        guard !applying else { return }
        let entries = entries()
        let existing = record
        if existing == nil, entries.isEmpty { return }
        if existing?.values == entries { return }
        do {
            try storage.save(RDAppSettings(entries: entries), changed: changed)
        } catch {
            RayonStorage.logger.error("saving the app settings for sync failed: \(error.localizedDescription)")
        }
    }

    /// Sets the record's settings here; one it does not have is reset.
    func pull() {
        guard let record, record.values != entries() else { return }
        let values = record.values
        applying = true
        defer { applying = false }
        for key in Self.keys {
            switch values[key] {
            case let .bool(value): defaults.set(value, forKey: key)
            case let .int(value): defaults.set(value, forKey: key)
            case let .string(value): defaults.set(value, forKey: key)
            case nil: defaults.removeObject(forKey: key)
            }
        }
        applied()
    }
}
