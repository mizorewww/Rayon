//
//  RayonStore.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/8.
//
//  What the interface shows of the user's data, and the way it changes it.
//  Every change is written to the database at once; there is nothing to
//  flush. Code off the main actor reads the database (`worker…`).
//

import Combine
import Foundation
import Synchronization
import Logger
#if canImport(UIKit)
    import UIKit
#endif

@MainActor
public final class RayonStore: ObservableObject {
    public static let shared: RayonStore = {
        // Before the store reads a setting (it trims the recent list to
        // the recent limit).
        LegacySettingsImport.run()
        let storage = RayonStorage.shared
        let store: RayonStore
        if storage.openProblem != nil {
            // The previous version's data is left for the database it
            // belongs in.
            store = RayonStore(storage: storage)
        } else {
            let legacy = LegacyStoreImport.runIfNeeded(into: storage)
            storage.purgeTombstones()
            store = RayonStore(storage: storage)
            if case let .blocked(reason) = legacy { store.importProblem = reason }
        }
        store.publishesWorkerSnapshot = true
        store.updateWorkerSnapshot()
        return store
    }()

    /// Whether this store is the one the worker lookups read: `shared`.
    var publishesWorkerSnapshot = false

    /// What the user must know at launch: the database is a newer
    /// version's or cannot be opened yet, or the previous version's data
    /// could not be brought over.
    public var launchProblem: String? {
        storage.openProblem ?? importProblem
    }

    private var importProblem: String?

    public nonisolated let storage: RayonStorage

    @Published public internal(set) var machines: [RDMachine] {
        didSet { updateWorkerSnapshot() }
    }

    @Published public internal(set) var identities: [RDIdentity] {
        didSet { updateWorkerSnapshot() }
    }
    /// Sorted by name.
    @Published public internal(set) var folders: [RDFolder]
    @Published public internal(set) var snippets: [RDSnippet]
    @Published public internal(set) var portForwards: [RDPortForward]
    @Published public var recentRecord: [RecentConnection] {
        didSet { persistRecent() }
    }

    init(storage: RayonStorage, defaults: UserDefaults = .standard) {
        self.storage = storage
        // bool(forKey:) also reads "YES"/"1" from the argument domain
        // (`-licenseAgreed YES`), and is false when the key is missing.
        licenseAgreed = defaults.bool(forKey: Self.licenseAgreedKey)

        machines = storage.records(RDMachine.self)
        identities = storage.records(RDIdentity.self)
        folders = Self.sorted(storage.records(RDFolder.self))
        snippets = storage.records(RDSnippet.self)
        portForwards = storage.records(RDPortForward.self)
        recentRecord = storage.recentConnections().compactMap(RecentConnection.init(record:))
        // The recent list follows its settings, wherever they are changed.
        AppSettings.remembersRecent.publisher
            .sink { [weak self] remembers in
                MainActor.assumeIsolated {
                    if !remembers { self?.recentRecord = [] }
                }
            }
            .store(in: &settingSubscriptions)
        AppSettings.recentLimit.publisher
            .sink { [weak self] limit in
                MainActor.assumeIsolated {
                    guard let self, self.recentRecord.count > max(1, limit) else { return }
                    self.recentRecord = Array(self.recentRecord.prefix(max(1, limit)))
                }
            }
            .store(in: &settingSubscriptions)
        #if canImport(UIKit)
            // Launched in the background before the first unlock, the
            // keychain gave no secrets; once it does, they are read.
            protectedDataObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        #endif
    }

    #if canImport(UIKit)
        private var protectedDataObserver: (any NSObjectProtocol)?
    #endif
    private var settingSubscriptions: Set<AnyCancellable> = []

    /// Reads everything from the database again, after it was changed from
    /// elsewhere (sync, a restored backup).
    public func reload() {
        machines = storage.records(RDMachine.self)
        identities = storage.records(RDIdentity.self)
        folders = Self.sorted(storage.records(RDFolder.self))
        snippets = storage.records(RDSnippet.self)
        portForwards = storage.records(RDPortForward.self)
        recentRecord = storage.recentConnections().compactMap(RecentConnection.init(record:))
    }

    // MARK: - State

    /// Not a setting: whether this device's user accepted the license.
    static let licenseAgreedKey = "licenseAgreed"

    @Published public var licenseAgreed: Bool {
        didSet { UserDefaults.standard.set(licenseAgreed, forKey: Self.licenseAgreedKey) }
    }

    @Published public var globalProgressInPresent: Bool = false
    public var globalProgressCount: Int = 0 {
        didSet { globalProgressInPresent = globalProgressCount != 0 }
    }
}

// MARK: - Lookups

public extension RayonStore {
    func machine(_ id: RDMachine.ID) -> RDMachine? {
        machines.first { $0.id == id }
    }

    func identity(_ id: RDIdentity.ID) -> RDIdentity? {
        identities.first { $0.id == id }
    }

    func snippet(_ id: RDSnippet.ID) -> RDSnippet? {
        snippets.first { $0.id == id }
    }

    func portForward(_ id: RDPortForward.ID) -> RDPortForward? {
        portForwards.first { $0.id == id }
    }

    func folder(_ id: RDFolder.ID?) -> RDFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    /// The identity the server signs in with; nil when it has none or the
    /// identity is gone.
    func associatedIdentity(for machine: RDMachine) -> RDIdentity? {
        machine.associatedIdentity.flatMap(identity)
    }

    /// The identities tried on a server that names none.
    var identitiesForAutoAuth: [RDIdentity] {
        Self.autoAuth(identities)
    }

    nonisolated static func autoAuth(_ identities: [RDIdentity]) -> [RDIdentity] {
        identities
            .filter(\.authenticAutomatically)
            // make sure not to reopen too many times
            .sorted { $0.username < $1.username }
    }
}

// MARK: - Changes

public extension RayonStore {
    enum SaveError: LocalizedError {
        case proxyJump(RDMachine.ProxyJumpError)

        public var errorDescription: String? {
            switch self {
            case let .proxyJump(error): error.errorDescription
            }
        }
    }

    /// Why the server cannot be saved as it is; nil when it can.
    func problem(saving machine: RDMachine) -> SaveError? {
        do {
            _ = try machine.proxyJumpChain { id in id == machine.id ? machine : self.machine(id) }
            return nil
        } catch let error as RDMachine.ProxyJumpError {
            return .proxyJump(error)
        } catch {
            return nil
        }
    }

    /// Saves the server; a change of its proxy jump that would make the
    /// jumps loop is refused (`problem(saving:)` says why). A server whose
    /// jumps loop already, as another device or a backup made them, is
    /// still saved when its jump does not change, so what it records of its
    /// connections is kept.
    @discardableResult
    func save(_ machine: RDMachine) -> Bool {
        if let problem = problem(saving: machine) {
            let existing = self.machine(machine.id)
            if existing?.transport != machine.transport || existing?.proxyJumpMachineID != machine.proxyJumpMachineID {
                Logger.database.errorFile("refusing to save \(machine.id): \(problem)")
                return false
            }
        }
        return persist(machine, into: \.machines)
    }

    /// A server offered as a jump server, and why it cannot be chosen
    /// when it cannot.
    struct JumpServerChoice: Identifiable {
        public let machine: RDMachine
        public let unavailableReason: String?
        public var id: RDMachine.ID { machine.id }

        /// The server and its address, then why it cannot be chosen.
        public var title: String {
            let title = "\(machine.name) (\(machine.remoteAddress):\(machine.remotePort))"
            return unavailableReason.map { "\(title) — \($0)" } ?? title
        }
    }

    /// The servers the server `id` (nil: a new one) could jump through:
    /// every SSH server but itself. One whose own jumps lead back to it is
    /// listed with the reason it cannot be chosen; UU Remote devices and
    /// servers without an address are not SSH servers to jump through and
    /// are left out. A remote desktop stays choosable: a VNC box may run
    /// sshd too, and connecting through it says so if it does not.
    func jumpServerChoices(for id: RDMachine.ID?) -> [JumpServerChoice] {
        var probe = id.flatMap(machine) ?? RDMachine(id: id ?? UUID())
        probe.transport = .proxyJump
        return machines.compactMap { candidate in
            guard candidate.id != probe.id, !candidate.isUURemoteDevice, candidate.hasAddress else { return nil }
            probe.proxyJumpMachineID = candidate.id
            if problem(saving: probe) != nil {
                return JumpServerChoice(machine: candidate, unavailableReason: "its jumps lead back here")
            }
            return JumpServerChoice(machine: candidate, unavailableReason: nil)
        }
    }

    @discardableResult
    func save(_ identity: RDIdentity) -> Bool {
        persist(identity, into: \.identities)
    }

    @discardableResult
    func save(_ snippet: RDSnippet) -> Bool {
        persist(snippet, into: \.snippets)
    }

    @discardableResult
    func save(_ forward: RDPortForward) -> Bool {
        guard forward.isComplete else {
            Logger.database.errorFile("refusing to save the incomplete forward \(forward.id)")
            return false
        }
        return persist(forward, into: \.portForwards)
    }

    @discardableResult
    func save(_ folder: RDFolder) -> Bool {
        defer { folders = Self.sorted(folders) }
        return persist(folder, into: \.folders)
    }

    func deleteMachines(_ ids: [RDMachine.ID]) {
        remove(RDMachine.self, ids: ids, from: \.machines)
        recentRecord.removeAll { if case let .machine(id) = $0 { ids.contains(id) } else { false } }
    }

    func deleteIdentities(_ ids: [RDIdentity.ID]) {
        remove(RDIdentity.self, ids: ids, from: \.identities)
    }

    func deleteSnippets(_ ids: [RDSnippet.ID]) {
        remove(RDSnippet.self, ids: ids, from: \.snippets)
    }

    func deletePortForwards(_ ids: [RDPortForward.ID]) {
        remove(RDPortForward.self, ids: ids, from: \.portForwards)
    }

    /// Records that the identity signed a session in, at most once a minute.
    func noteIdentityUsed(_ id: RDIdentity.ID, at date: Date = Date()) {
        updateIdentity(id) { identity in
            guard abs(identity.lastRecentUsed.timeIntervalSince(date)) > 60 else { return }
            identity.lastRecentUsed = date
        }
    }

    /// Changes some fields of the server as it is saved now: the copy here
    /// may be older than a change another device made, which saving it
    /// would undo. The change must not touch its jumps, which `save`
    /// checks. Returns the server as saved.
    @discardableResult
    func updateMachine(_ id: RDMachine.ID, _ change: (inout RDMachine) -> Void) -> RDMachine? {
        update(RDMachine.self, id: id, into: \.machines, change)
    }

    /// `updateMachine`, for an identity.
    @discardableResult
    func updateIdentity(_ id: RDIdentity.ID, _ change: (inout RDIdentity) -> Void) -> RDIdentity? {
        update(RDIdentity.self, id: id, into: \.identities, change)
    }

    /// `updateMachine`, for a folder.
    @discardableResult
    func updateFolder(_ id: RDFolder.ID, _ change: (inout RDFolder) -> Void) -> RDFolder? {
        defer { folders = Self.sorted(folders) }
        return update(RDFolder.self, id: id, into: \.folders, change)
    }
}

extension RayonStore {

    func persist<T: StoredRecord>(_ record: T, into path: ReferenceWritableKeyPath<RayonStore, [T]>) -> Bool {
        do {
            let saved = try storage.save(record)
            if let index = self[keyPath: path].firstIndex(where: { $0.id == saved.id }) {
                self[keyPath: path][index] = saved
            } else {
                self[keyPath: path].append(saved)
            }
            return true
        } catch {
            Logger.database.errorFile("saving \(public: T.tableName) \(record.id) failed: \(error)")
            return false
        }
    }

    func update<T: StoredRecord>(
        _: T.Type,
        id: UUID,
        into path: ReferenceWritableKeyPath<RayonStore, [T]>,
        _ change: (inout T) -> Void
    ) -> T? {
        do {
            guard let saved = try storage.update(T.self, id: id, change) else { return nil }
            if let index = self[keyPath: path].firstIndex(where: { $0.id == saved.id }) {
                self[keyPath: path][index] = saved
            }
            return saved
        } catch {
            Logger.database.errorFile("updating \(public: T.tableName) \(id) failed: \(error)")
            return nil
        }
    }

    func remove<T: StoredRecord>(_: T.Type, ids: [UUID], from path: ReferenceWritableKeyPath<RayonStore, [T]>) {
        guard !ids.isEmpty else { return }
        do {
            try storage.delete(T.self, ids: ids)
            self[keyPath: path].removeAll { ids.contains($0.id) }
        } catch {
            Logger.database.errorFile("deleting from \(public: T.tableName) failed: \(error)")
        }
    }

    nonisolated static func sorted(_ folders: [RDFolder]) -> [RDFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Off the main actor

/// What code off the main actor reads of the shared store's servers and
/// identities: a copy kept in step with them, so a lookup (made from a
/// view's body too) costs no database read and no keychain query.
struct WorkerSnapshot: Sendable {
    var machines: [RDMachine.ID: RDMachine] = [:]
    var identities: [RDIdentity.ID: RDIdentity] = [:]
}

extension RayonStore {
    nonisolated static let workerSnapshot = Mutex(WorkerSnapshot())

    func updateWorkerSnapshot() {
        guard publishesWorkerSnapshot else { return }
        let snapshot = WorkerSnapshot(
            machines: Dictionary(machines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            identities: Dictionary(identities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )
        Self.workerSnapshot.withLock { $0 = snapshot }
    }
}

/// Code off the main actor cannot reach `shared`; it reads its snapshot.
public extension RayonStore {
    nonisolated static func workerMachine(for id: RDMachine.ID) -> RDMachine? {
        workerSnapshot.withLock { $0.machines[id] }
    }

    /// The identity the server signs in with.
    nonisolated static func workerAssociatedIdentity(for machine: RDMachine) -> RDIdentity? {
        guard let id = machine.associatedIdentity else { return nil }
        return workerSnapshot.withLock { $0.identities[id] }
    }

    /// `identitiesForAutoAuth`.
    nonisolated static var workerIdentitiesForAutoAuth: [RDIdentity] {
        Self.autoAuth(workerSnapshot.withLock { Array($0.identities.values) })
    }
}
