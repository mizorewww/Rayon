//
//  TerminalSettingsSync.swift
//  RayonModule
//
//  Keeps the terminal settings record and config.ghostty in step: a change
//  made here is written to the record (and so queued for iCloud), and a
//  record from another device is applied to the terminals.
//

import Foundation
import RayonTerminal

@MainActor
final class TerminalSettingsSync {
    private let storage: RayonStorage
    private let settings: TerminalSettings
    private var observers: [any NSObjectProtocol] = []

    init(storage: RayonStorage, settings: TerminalSettings) {
        self.storage = storage
        self.settings = settings
    }

    /// Settles which side is newer, then follows both.
    func start() {
        guard observers.isEmpty else { return }
        let written = TerminalConfigurationSync.lastWritten(settings)
        if let record = storage.record(RDTerminalSettings.self, id: RDTerminalSettings.recordID),
           written.map({ $0 <= record.modified }) ?? true
        {
            pull()
        } else {
            push(changed: written)
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: TerminalConfigurationSync.didChange, object: settings, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: RayonStorage.didMergeRemoteChanges, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        })
    }

    /// Writes what this device has, if it differs from the record. A first
    /// record from settings that have not changed keeps the file's time, so
    /// it does not win over another device's later change.
    func push(changed: Date? = nil) {
        let entries = TerminalConfigurationSync.entries(of: settings)
        let existing = storage.record(RDTerminalSettings.self, id: RDTerminalSettings.recordID)
        if existing == nil, entries.isEmpty { return }
        if existing?.values == entries { return }
        do {
            try storage.save(RDTerminalSettings(entries: entries), changed: changed)
        } catch {
            RayonStorage.logger.error("saving the terminal settings for sync failed: \(error.localizedDescription)")
        }
    }

    /// Applies the record's settings.
    func pull() {
        guard let record = storage.record(RDTerminalSettings.self, id: RDTerminalSettings.recordID) else { return }
        TerminalConfigurationSync.adopt(record.values, into: settings)
    }
}
