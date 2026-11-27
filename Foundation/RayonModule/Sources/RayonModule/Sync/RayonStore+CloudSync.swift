//
//  RayonStore+CloudSync.swift
//  RayonModule
//
//  The interface's side of iCloud sync: the user's choices, the status to
//  show, and the lists read again when another device's changes arrive.
//

import Combine
import Foundation
import RayonTerminal

@MainActor
public final class CloudSyncModel: ObservableObject {
    public static let shared = CloudSyncModel(store: .shared)

    @Published public var preferences: CloudSyncPreferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.store()
            let preferences = preferences
            Task { await CloudSync.shared.apply(preferences) }
        }
    }

    @Published public private(set) var status: CloudSync.Status = .off

    private let terminalSettings: TerminalSettingsSync
    private let appSettings: AppSettingsSync
    private var observers: [any NSObjectProtocol] = []

    init(store: RayonStore, terminal: TerminalSettings = .shared) {
        terminalSettings = TerminalSettingsSync(storage: store.storage, settings: terminal)
        appSettings = AppSettingsSync(storage: store.storage)
        preferences = .stored
        observers.append(NotificationCenter.default.addObserver(
            forName: CloudSync.statusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let status = note.object as? CloudSync.Status else { return }
            MainActor.assumeIsolated { self?.status = status }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: RayonStorage.didOpen, object: store.storage, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let preferences = self?.preferences else { return }
                Task { await CloudSync.shared.apply(preferences) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: RayonStorage.didMergeRemoteChanges, object: nil, queue: .main
        ) { [weak store] _ in
            MainActor.assumeIsolated { store?.reload() }
        })
    }

    /// Starts sync if the user turned it on. Called once at launch.
    public func start() {
        terminalSettings.start()
        appSettings.start()
        let preferences = preferences
        Task { await CloudSync.shared.apply(preferences) }
    }

    /// After the iCloud account changed: sync this device's data with the
    /// account signed in now.
    public func resumeWithCurrentAccount() {
        Task { await CloudSync.shared.resumeWithCurrentAccount() }
    }

    public func syncNow() {
        Task { await CloudSync.shared.syncNow() }
    }

    /// Deletes what Rayon keeps in iCloud and turns sync off; nil, or why
    /// it could not.
    public func deleteCloudData() async -> String? {
        do {
            try await CloudSync.shared.deleteCloudData()
            preferences.isOn = false
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Whether "Sync Now" has something to do.
    public var canSyncNow: Bool {
        switch status {
        case .idle, .failed, .noAccount: return true
        case .off, .unavailable, .accountChanged, .syncing: return false
        }
    }

    /// What to say under the switch.
    public var statusText: String {
        switch status {
        case .off: return String(localized: "Off", bundle: .module)
        case .unavailable: return String(localized: "This build is not signed for iCloud.", bundle: .module)
        case .noAccount: return String(localized: "Sign in to iCloud to sync.", bundle: .module)
        case .accountChanged: return String(localized: "Paused: the iCloud account changed. Nothing has been sent to the account signed in now.", bundle: .module)
        case .syncing: return String(localized: "Syncing…", bundle: .module)
        case let .idle(lastSync?): return String(localized: "Synced \(lastSync.formatted(.relative(presentation: .named)))", bundle: .module)
        case .idle(nil): return String(localized: "Up to date", bundle: .module)
        case let .failed(message): return message
        }
    }
}
