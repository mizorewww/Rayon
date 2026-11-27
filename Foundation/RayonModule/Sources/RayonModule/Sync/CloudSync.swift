//
//  CloudSync.swift
//  RayonModule
//
//  iCloud sync with CKSyncEngine, after FlowDown's: records go to a zone of
//  the user's private CloudKit database one by one, as they change; the
//  upload queue in the database says what is still to send, and records
//  from other devices are merged by the time they were changed. Nothing is
//  sent or taken for kinds of records the user leaves out.
//

import CloudKit
import Foundation
import Logger

public actor CloudSync {
    public static let containerIdentifier = "iCloud.me.mizorewww.rayon"
    public static let shared = CloudSync(storage: .shared)


    public enum Status: Equatable, Sendable {
        case off
        /// The build is not signed for iCloud.
        case unavailable
        case syncing
        case idle(lastSync: Date?)
        case failed(String)
    }

    /// Posted on the main thread with the new `Status` as the object.
    public static let statusDidChange = Notification.Name("me.mizorewww.rayon.sync.statusDidChange")

    private let storage: RayonStorage
    private var engine: CKSyncEngine?
    private var preferences = CloudSyncPreferences()
    private var lastSync: Date?
    private var observer: (any NSObjectProtocol)?
    /// Records fetched from iCloud that could not be merged here (the
    /// keychain locked, say), by record name; fetched and merged again
    /// after each fetch. The engine's change token is past them already.
    private(set) var failedMerges: Set<String>
    private let retryURL: URL

    init(storage: RayonStorage) {
        self.storage = storage
        retryURL = storage.databaseURL.deletingLastPathComponent().appendingPathComponent("sync-retry.json")
        failedMerges = (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: retryURL))) ?? []
    }

    private var stateURL: URL {
        storage.databaseURL.deletingLastPathComponent().appendingPathComponent("sync-state.json")
    }

    /// The tables the engine state was built with: records of any other
    /// table it fetched were dropped.
    private var scopesURL: URL {
        storage.databaseURL.deletingLastPathComponent().appendingPathComponent("sync-scopes.json")
    }

    /// Where earlier builds left the files of large records sent as
    /// assets; removed at start.
    private var assetDirectory: URL {
        storage.databaseURL.deletingLastPathComponent().appendingPathComponent("SyncAssets", isDirectory: true)
    }

    /// Whether this build may use CloudKit: without the entitlement,
    /// touching a container ends the app.
    public nonisolated static var isAvailable: Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String]
            else { return false }
            return services.contains("CloudKit")
        #else
            // A build installed with a provisioning profile (development,
            // ad hoc) has iCloud only when the profile grants the container;
            // one from the App Store carries no profile and always has.
            guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
                  let data = try? Data(contentsOf: url)
            else { return true }
            return data.range(of: Data(containerIdentifier.utf8)) != nil
        #endif
    }

    // MARK: - Turning it on and off

    /// Follows the preferences: starts, stops or changes what is synced.
    public func apply(_ new: CloudSyncPreferences) async {
        let old = preferences
        preferences = new
        guard new.isOn else {
            stop()
            // What iCloud has is forgotten; what is queued stays, so a
            // deletion made while off still reaches iCloud. With no engine
            // state, turning sync on starts as a sign-in, which queues
            // everything again.
            storage.forgetSyncState()
            saveState(nil)
            publish(.off)
            return
        }
        guard Self.isAvailable else {
            publish(.unavailable)
            return
        }
        // Its engine state lies beside the database: until that opens, the
        // engine would start over without it. `CloudSyncModel` applies the
        // preferences again once it does.
        guard storage.openIfNeeded() else {
            publish(.failed(storage.openProblem ?? "The database cannot be opened."))
            return
        }
        let tables = new.syncedTables
        if Self.needsRefetch(covered: loadScopes(), syncing: tables) {
            // A kind let in again: what other devices changed while it was
            // left out came and was dropped, and the engine's change token
            // is past it. Everything is fetched again, and what is here
            // goes out on top of it.
            Logger.syncEngine.infoFile("sync scopes widened; fetching everything again")
            stop()
            saveState(nil)
            storage.removeAllSystemFields()
        }
        saveScopes(tables)
        if engine == nil {
            start()
        } else if new != old {
            scheduleUploads()
        }
        await syncNow()
    }

    /// Whether the engine state, built while only `covered` synced (nil:
    /// unknown, or none yet), lacks changes of a table that syncs now.
    static func needsRefetch(covered: Set<String>?, syncing: Set<String>) -> Bool {
        guard let covered else { return false }
        return !syncing.isSubset(of: covered)
    }

    private func start() {
        try? FileManager.default.removeItem(at: assetDirectory)
        var configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoding.zoneID))])
        observer = NotificationCenter.default.addObserver(
            forName: RayonStorage.didQueueChanges,
            object: storage,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.scheduleUploads() }
        }
        scheduleUploads()
        Logger.syncEngine.infoFile("sync started")
    }

    private func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine = nil
    }

    /// Deletes what Rayon keeps in iCloud and stops syncing here; what is
    /// on this device stays. A device still syncing puts its own back.
    public func deleteCloudData() async throws {
        guard Self.isAvailable else { throw CKError(.notAuthenticated) }
        stop()
        publish(.syncing)
        do {
            try await CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
                .deleteRecordZone(withID: CloudRecordCoding.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing there.
        } catch {
            // Sync stays on: without its engine back, Sync Now and every
            // change would do nothing until the next launch.
            if preferences.isOn { start() }
            publish(.failed(error.localizedDescription))
            throw error
        }
        preferences.isOn = false
        storage.forgetSyncState()
        saveState(nil)
        publish(.off)
    }

    /// Fetches and sends now, instead of when the system gets to it.
    public func syncNow() async {
        guard let engine else { return }
        publish(.syncing)
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            lastSync = Date()
            publish(.idle(lastSync: lastSync))
        } catch {
            Logger.syncEngine.errorFile("sync failed: \(error.localizedDescription)")
            publish(.failed(error.localizedDescription))
        }
    }

    // MARK: - State

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func loadScopes() -> Set<String>? {
        guard FileManager.default.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: scopesURL)
        else { return nil }
        return try? JSONDecoder().decode(Set<String>.self, from: data)
    }

    private func saveScopes(_ tables: Set<String>) {
        try? JSONEncoder().encode(tables).write(to: scopesURL, options: .atomic)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization?) {
        guard let state else {
            // Without a change token everything is fetched again, the
            // records that failed to merge among it.
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scopesURL)
            setFailedMerges([])
            return
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func setFailedMerges(_ names: Set<String>) {
        guard names != failedMerges else { return }
        failedMerges = names
        if names.isEmpty {
            try? FileManager.default.removeItem(at: retryURL)
        } else {
            try? JSONEncoder().encode(names).write(to: retryURL, options: .atomic)
        }
    }

    private func publish(_ status: Status) {
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.statusDidChange, object: status)
        }
    }

    // MARK: - Sending

    /// Tells the engine about every queued change of a kind that syncs,
    /// and takes back what it holds of kinds that no longer do: their
    /// changes stay queued here, for when they sync again.
    private func scheduleUploads() {
        guard let engine else { return }
        let excluded = engine.state.pendingRecordZoneChanges.filter { !syncs($0) }
        if !excluded.isEmpty { engine.state.remove(pendingRecordZoneChanges: excluded) }
        let pending = Set(engine.state.pendingRecordZoneChanges)
        let changes = storage.pendingUploads()
            .filter { preferences.syncs(table: $0.tableName) }
            .map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CloudRecordCoding.recordID(table: $0.tableName, id: $0.objectId)) }
            .filter { !pending.contains($0) }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func syncs(_ change: CKSyncEngine.PendingRecordZoneChange) -> Bool {
        switch change {
        case let .saveRecord(id), let .deleteRecord(id): syncs(id)
        @unknown default: false
        }
    }

    private func syncs(_ id: CKRecord.ID) -> Bool {
        RayonStorage.parse(recordName: id.recordName).map { preferences.syncs(table: $0.table) } ?? false
    }

    func ckRecord(for id: CKRecord.ID) -> CKRecord? {
        // A kind left out after its change was handed to the engine.
        guard syncs(id), let record = storage.recordToSend(named: id.recordName)
        else { return nil }
        // Sending it would send its secrets as empty, and every device
        // would clear its own. It stays queued until they can be read.
        guard !record.secretsUnread else {
            Logger.syncEngine.errorFile("not sending \(id.recordName): its secrets cannot be read now")
            return nil
        }
        func encode<T: StoredRecord>(_ record: T) -> CKRecord? {
            do {
                return try CloudRecordCoding.ckRecord(for: record, systemFields: storage.systemFields(for: id.recordName))
            } catch {
                Logger.syncEngine.errorFile("not sending \(id.recordName): \(error.localizedDescription)")
                return nil
            }
        }
        return encode(record)
    }

    // MARK: - Receiving

    /// Writes a record from iCloud here, when its kind syncs; whether
    /// that changed what is here. Its system fields are kept only once it
    /// is merged: with them, the version here would be sent over the one it
    /// failed to take. One that fails is merged again later.
    func receive(_ ck: CKRecord) -> Bool {
        let name = ck.recordID.recordName
        guard let (table, _) = RayonStorage.parse(recordName: name),
              preferences.syncs(table: table)
        else {
            setFailedMerges(failedMerges.subtracting([name]))
            return false
        }
        do {
            let record = try CloudRecordCoding.decode(ck)
            func merge<T: StoredRecord>(_ record: T) throws -> Bool {
                try storage.mergeRemote(record) == .tookRemote
            }
            let took = try merge(record)
            storage.setSystemFields(CloudRecordCoding.encode(systemFields: ck), for: name)
            setFailedMerges(failedMerges.subtracting([name]))
            return took
        } catch {
            Logger.syncEngine.errorFile("could not take \(name), retrying after the next fetch: \(error.localizedDescription)")
            setFailedMerges(failedMerges.union([name]))
            return false
        }
    }

    /// Fetches the records that failed to merge and merges them again, in
    /// requests of at most 400 records, as many as CloudKit takes at once.
    func retryFailedMerges(
        fetch: @Sendable ([CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]
    ) async {
        let names = Array(failedMerges)
        var changed = false
        for start in stride(from: 0, to: names.count, by: 400) {
            let ids = names[start ..< min(start + 400, names.count)].map { CKRecord.ID(recordName: $0, zoneID: CloudRecordCoding.zoneID) }
            let results: [CKRecord.ID: Result<CKRecord, any Error>]
            do {
                results = try await fetch(ids)
            } catch {
                Logger.syncEngine.errorFile("fetching records to merge again failed: \(error.localizedDescription)")
                break
            }
            for (id, result) in results {
                switch result {
                case let .success(record):
                    changed = receive(record) || changed
                case let .failure(error as CKError) where error.code == .unknownItem:
                    // Deleted there since: the deletion comes with a fetch.
                    setFailedMerges(failedMerges.subtracting([id.recordName]))
                case .failure:
                    break
                }
            }
        }
        if changed { notifyMerged() }
    }

    private func notifyMerged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: RayonStorage.didMergeRemoteChanges, object: nil)
        }
    }

    // MARK: - Events

    func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case let .stateUpdate(update):
            saveState(update.stateSerialization)

        case let .accountChange(change):
            switch change.changeType {
            case .signIn:
                try? storage.enqueueEverything()
            case .signOut, .switchAccounts:
                // Another account has none of these: forget what the last
                // one had seen and send everything to the next.
                storage.removeAllSystemFields()
                saveState(nil)
                try? storage.enqueueEverything()
            @unknown default:
                break
            }

        case let .fetchedDatabaseChanges(changes):
            for deletion in changes.deletions where deletion.zoneID == CloudRecordCoding.zoneID {
                // The zone was deleted (iCloud data removed in Settings):
                // what is here goes up again into a new one.
                storage.removeAllSystemFields()
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoding.zoneID))])
                try? storage.enqueueEverything()
            }

        case .didFetchChanges:
            let database = engine.database
            Task { await retryFailedMerges { try await database.records(for: $0) } }

        case let .fetchedRecordZoneChanges(changes):
            var changed = false
            for modification in changes.modifications {
                changed = receive(modification.record) || changed
            }
            for deletion in changes.deletions {
                guard let (table, id) = RayonStorage.parse(recordName: deletion.recordID.recordName),
                      preferences.syncs(table: table)
                else { continue }
                storage.removeForSync(table: table, id: id)
                setFailedMerges(failedMerges.subtracting([deletion.recordID.recordName]))
                changed = true
            }
            if changed { notifyMerged() }

        case let .sentRecordZoneChanges(sent):
            for record in sent.savedRecords {
                storage.setSystemFields(CloudRecordCoding.encode(systemFields: record), for: record.recordID.recordName)
                if let (table, id) = RayonStorage.parse(recordName: record.recordID.recordName),
                   let modified = record[CloudRecordCoding.Field.modified] as? Int64
                {
                    storage.dequeue(table: table, id: id, sentModified: Date(timeIntervalSince1970: TimeInterval(modified) / 1000))
                }
            }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var zoneMissing = false
            var changed = false
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // Another device saved it first: merge theirs, and send
                    // ours again on top of it if ours is newer. Theirs not
                    // merged, ours waits, or it would replace theirs.
                    if let server = failure.error.serverRecord {
                        changed = receive(server) || changed
                        if !failedMerges.contains(id.recordName) { retry.append(.saveRecord(id)) }
                    }
                case .zoneNotFound:
                    zoneMissing = true
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    storage.setSystemFields(nil, for: id.recordName)
                    retry.append(.saveRecord(id))
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .operationCancelled, .requestRateLimited:
                    break
                default:
                    Logger.syncEngine.errorFile("iCloud refused \(id.recordName): \(failure.error.localizedDescription)")
                }
            }
            if zoneMissing {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecordCoding.zoneID))])
            }
            if !retry.isEmpty {
                scheduleUploads()
            }
            if changed { notifyMerged() }

        default:
            break
        }
    }

    func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) && syncs($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.ckRecord(for: id)
        }
    }
}

extension CloudSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine stopped (sync turned off, or started afresh) may still
        // deliver; its state must not be saved over the current one.
        guard syncEngine === engine else { return }
        handle(event, engine: syncEngine)
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        return await nextBatch(context, engine: syncEngine)
    }
}
