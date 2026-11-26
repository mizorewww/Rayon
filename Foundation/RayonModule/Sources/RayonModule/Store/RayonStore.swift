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
import os

@MainActor
public final class RayonStore: ObservableObject {
    public static let shared: RayonStore = {
        LegacyStoreImport.runIfNeeded(into: .shared)
        RayonStorage.shared.purgeTombstones()
        return RayonStore(storage: .shared)
    }()

    public nonisolated let storage: RayonStorage

    @Published public internal(set) var machines: [RDMachine]
    @Published public internal(set) var identities: [RDIdentity]
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
        licenseAgreed = defaults.bool(forKey: Key.licenseAgreed)
        storeRecent = Self.bool(Key.storeRecent, default: true, in: defaults)
        saveTemporarySession = Self.bool(Key.saveTemporarySession, default: true, in: defaults)
        let savedTimeout = Self.int(Key.timeout, default: 5, in: defaults)
        timeout = savedTimeout > 0 ? savedTimeout : 5
        reducedViewEffects = Self.bool(Key.reducedViewEffects, default: false, in: defaults)
        disableConformation = Self.bool(Key.disableConformation, default: false, in: defaults)
        monitorInterval = Self.int(Key.monitorInterval, default: 3, in: defaults)
        terminalFontSize = Self.int(Key.terminalFontSize, default: 14, in: defaults)
        terminalCopyOnSelect = Self.bool(Key.terminalCopyOnSelect, default: true, in: defaults)
        terminalClipboardSharing = Self.bool(Key.terminalClipboardSharing, default: true, in: defaults)
        maxRecentRecordCount = Self.int(Key.maxRecentRecordCount, default: 8, in: defaults)
        openInterfaceAutomatically = Self.bool(Key.openInterfaceAutomatically, default: true, in: defaults)
        machineRedacted = RDMachine.RedactedLevel(rawValue: defaults.integer(forKey: Key.machineRedacted)) ?? .none

        machines = storage.records(RDMachine.self)
        identities = storage.records(RDIdentity.self)
        folders = Self.sorted(storage.records(RDFolder.self))
        snippets = storage.records(RDSnippet.self)
        portForwards = storage.records(RDPortForward.self)
        recentRecord = storage.recentConnections().compactMap(RecentConnection.init(record:))
    }

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

    // MARK: - Settings

    enum Key {
        static let licenseAgreed = "licenseAgreed"
        static let storeRecent = "me.mizorewww.rayon.storeRecent"
        static let saveTemporarySession = "me.mizorewww.rayon.saveTemporarySession"
        static let timeout = "me.mizorewww.rayon.timeout"
        static let reducedViewEffects = "me.mizorewww.rayon.reducedViewEffects"
        static let disableConformation = "me.mizorewww.rayon.disableConformation"
        static let monitorInterval = "me.mizorewww.rayon.monitorInterval"
        static let terminalFontSize = "me.mizorewww.rayon.terminalFontSize"
        static let terminalCopyOnSelect = "me.mizorewww.rayon.terminalCopyOnSelect"
        static let terminalClipboardSharing = "me.mizorewww.rayon.terminalClipboardSharing"
        static let maxRecentRecordCount = "me.mizorewww.rayon.maxRecentRecordCount"
        static let openInterfaceAutomatically = "me.mizorewww.rayon.openInterfaceAutomatically"
        static let machineRedacted = "me.mizorewww.rayon.machineRedacted"
    }

    nonisolated static func int(_ key: String, default value: Int, in defaults: UserDefaults) -> Int {
        defaults.object(forKey: key) == nil ? value : defaults.integer(forKey: key)
    }

    nonisolated static func bool(_ key: String, default value: Bool, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    @Published public var licenseAgreed: Bool {
        didSet { UserDefaults.standard.set(licenseAgreed, forKey: Key.licenseAgreed) }
    }

    @Published public var globalProgressInPresent: Bool = false
    public var globalProgressCount: Int = 0 {
        didSet { globalProgressInPresent = globalProgressCount != 0 }
    }

    @Published public var timeout: Int {
        didSet { UserDefaults.standard.set(timeout, forKey: Key.timeout) }
    }

    @Published public var monitorInterval: Int {
        didSet { UserDefaults.standard.set(monitorInterval, forKey: Key.monitorInterval) }
    }

    public var timeoutNumber: NSNumber {
        NSNumber(value: timeout)
    }

    @Published public var openInterfaceAutomatically: Bool {
        didSet { UserDefaults.standard.set(openInterfaceAutomatically, forKey: Key.openInterfaceAutomatically) }
    }

    @Published public var machineRedacted: RDMachine.RedactedLevel {
        didSet { UserDefaults.standard.set(machineRedacted.rawValue, forKey: Key.machineRedacted) }
    }

    @Published public var saveTemporarySession: Bool {
        didSet { UserDefaults.standard.set(saveTemporarySession, forKey: Key.saveTemporarySession) }
    }

    @Published public var storeRecent: Bool {
        didSet {
            UserDefaults.standard.set(storeRecent, forKey: Key.storeRecent)
            if !storeRecent { recentRecord = [] }
        }
    }

    @Published public var reducedViewEffects: Bool {
        didSet { UserDefaults.standard.set(reducedViewEffects, forKey: Key.reducedViewEffects) }
    }

    @Published public var disableConformation: Bool {
        didSet { UserDefaults.standard.set(disableConformation, forKey: Key.disableConformation) }
    }

    public var maxRecentRecordCount: Int {
        didSet { UserDefaults.standard.set(maxRecentRecordCount, forKey: Key.maxRecentRecordCount) }
    }

    @Published public var terminalFontSize: Int {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: Key.terminalFontSize) }
    }

    /// A finished selection in a terminal is copied to the clipboard.
    @Published public var terminalCopyOnSelect: Bool {
        didSet { UserDefaults.standard.set(terminalCopyOnSelect, forKey: Key.terminalCopyOnSelect) }
    }

    /// Programs on the remote host may read and write the clipboard (OSC 52).
    @Published public var terminalClipboardSharing: Bool {
        didSet { UserDefaults.standard.set(terminalClipboardSharing, forKey: Key.terminalClipboardSharing) }
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

    /// Saves the server; a server whose proxy jumps would loop is refused.
    @discardableResult
    func save(_ machine: RDMachine) -> Bool {
        if let problem = problem(saving: machine) {
            Self.logger.error("refusing to save \(machine.id): \(problem.localizedDescription)")
            return false
        }
        return persist(machine, into: \.machines)
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
            Self.logger.error("refusing to save the incomplete forward \(forward.id)")
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
        guard var identity = identity(id), abs(identity.lastRecentUsed.timeIntervalSince(date)) > 60 else { return }
        identity.lastRecentUsed = date
        save(identity)
    }
}

extension RayonStore {
    static let logger = Logger(subsystem: "me.mizorewww.rayon", category: "store")

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
            Self.logger.error("saving \(T.tableName) \(record.id) failed: \(error.localizedDescription)")
            return false
        }
    }

    func remove<T: StoredRecord>(_: T.Type, ids: [UUID], from path: ReferenceWritableKeyPath<RayonStore, [T]>) {
        guard !ids.isEmpty else { return }
        do {
            try storage.delete(T.self, ids: ids)
            self[keyPath: path].removeAll { ids.contains($0.id) }
        } catch {
            Self.logger.error("deleting from \(T.tableName) failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func sorted(_ folders: [RDFolder]) -> [RDFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Off the main actor

/// Code off the main actor cannot reach `shared`; it reads the database
/// and the defaults directly.
public extension RayonStore {
    /// The server, read from the database.
    nonisolated static func workerMachine(for id: RDMachine.ID) -> RDMachine? {
        RayonStorage.shared.record(RDMachine.self, id: id)
    }

    /// The identity the server signs in with, read from the database.
    nonisolated static func workerAssociatedIdentity(for machine: RDMachine) -> RDIdentity? {
        machine.associatedIdentity.flatMap { RayonStorage.shared.record(RDIdentity.self, id: $0) }
    }

    /// `identitiesForAutoAuth`, read from the database.
    nonisolated static var workerIdentitiesForAutoAuth: [RDIdentity] {
        Self.autoAuth(RayonStorage.shared.records(RDIdentity.self))
    }

    nonisolated static var workerTimeoutNumber: NSNumber {
        let value = int(Key.timeout, default: 5, in: .standard)
        return NSNumber(value: value > 0 ? value : 5)
    }

    nonisolated static var workerMonitorInterval: Int {
        int(Key.monitorInterval, default: 3, in: .standard)
    }

    nonisolated static var workerTerminalFontSize: Int {
        int(Key.terminalFontSize, default: 14, in: .standard)
    }
}
