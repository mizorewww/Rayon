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

    private let defaults: UserDefaults
    private let record: SettingsRecordSync<RDAppSettings>
    private var observers: [any NSObjectProtocol] = []

    /// `applied` runs after another device's settings were set.
    init(storage: RayonStorage, defaults: UserDefaults, applied: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        record = SettingsRecordSync(storage: storage, syncs: Self.keys.contains, read: { Self.entries(in: defaults) }) { values in
            Self.set(values, in: defaults)
            applied()
        }
    }

    /// A change made here is written to the record as it is made, so the
    /// record is the newer side at launch once it exists. Before, these
    /// settings are written as old, so another device's changes win.
    func start() {
        guard observers.isEmpty else { return }
        if record.record != nil {
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
    static func entries(in defaults: UserDefaults) -> [String: RDAppSettings.Value] {
        var entries: [String: RDAppSettings.Value] = [:]
        for key in keys {
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

    /// Writes what changed here to the record.
    func push(changed: Date? = nil) {
        record.push(changed: changed)
    }

    /// Sets the record's settings here.
    func pull() {
        record.pull()
    }

    /// Sets `values` here; a setting they do not have is reset.
    private static func set(_ values: [String: RDAppSettings.Value], in defaults: UserDefaults) {
        for key in keys {
            switch values[key] {
            case let .bool(value): defaults.set(value, forKey: key)
            case let .int(value): defaults.set(value, forKey: key)
            case let .string(value): defaults.set(value, forKey: key)
            case nil: defaults.removeObject(forKey: key)
            }
        }
    }
}
