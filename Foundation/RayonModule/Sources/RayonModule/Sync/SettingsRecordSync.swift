//
//  SettingsRecordSync.swift
//  RayonModule
//
//  One settings record (the app settings, the terminal settings) kept in
//  step with the settings it stands for. Only what changed here since the
//  two last agreed goes into the record: a record from another device that
//  is merged before it is applied here is never overwritten by the values
//  it replaced, whatever runs in between.
//

import Foundation

/// A record holding settings as values by key.
protocol SettingsRecord: StoredRecord {
    associatedtype Value: Equatable
    static var recordID: UUID { get }
    init(entries: [String: Value])
    var values: [String: Value] { get }
}

extension RDAppSettings: SettingsRecord {}
extension RDTerminalSettings: SettingsRecord {}

@MainActor
final class SettingsRecordSync<Record: SettingsRecord> {
    typealias Values = [String: Record.Value]

    private let storage: RayonStorage
    private let syncs: (String) -> Bool
    private let read: () -> Values?
    private let apply: (Values) -> Void
    /// The settings here when they and the record last agreed: what differs
    /// from them was changed here since.
    private var synced: Values?
    /// Set while the record's settings are applied: each one set is not a
    /// change here.
    private var applying = false

    /// `syncs` says which of the record's keys this device takes; `read`
    /// gives the settings here, or nil when they cannot be read (then
    /// nothing is written or applied); `apply` sets them.
    init(
        storage: RayonStorage,
        syncs: @escaping (String) -> Bool,
        read: @escaping () -> Values?,
        apply: @escaping (Values) -> Void
    ) {
        self.storage = storage
        self.syncs = syncs
        self.read = read
        self.apply = apply
    }

    var record: Record? {
        storage.record(Record.self, id: Record.recordID)
    }

    /// Writes the changes made here to the record, as changed at `changed`
    /// (now by default), and applies what else the record has. The first
    /// time, the settings here win over the record's.
    func push(changed: Date? = nil) {
        reconcile(preferringLocal: true, changed: changed)
    }

    /// Applies the record's settings here, keeping changes made here since
    /// the last sync (which go into the record). The first time, the
    /// record's win over the settings here.
    func pull() {
        reconcile(preferringLocal: false, changed: nil)
    }

    private func reconcile(preferringLocal: Bool, changed: Date?) {
        guard !applying, let local = read() else { return }
        let remote = record?.values.filter { syncs($0.key) }
        var values: Values
        if let synced {
            values = remote ?? synced
            for key in Set(local.keys).union(synced.keys) where local[key] != synced[key] {
                values[key] = local[key]
            }
        } else if let remote, !preferringLocal {
            values = remote
        } else {
            values = local
        }
        if values != local {
            applying = true
            apply(values)
            applying = false
        }
        synced = read() ?? values
        guard values != remote, remote != nil || !values.isEmpty else { return }
        do {
            try storage.save(Record(entries: values), changed: changed)
        } catch {
            RayonStorage.logger.error("saving \(Record.tableName) for sync failed: \(error.localizedDescription)")
        }
    }
}
