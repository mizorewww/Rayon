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
            preferences.save(to: defaults)
            let preferences = preferences
            Task { await CloudSync.shared.apply(preferences) }
        }
    }

    @Published public private(set) var status: CloudSync.Status = .off

    private let defaults: UserDefaults
    private let terminalSettings: TerminalSettingsSync
    private var observers: [any NSObjectProtocol] = []

    init(store: RayonStore, defaults: UserDefaults = .standard, terminal: TerminalSettings = .shared) {
        self.defaults = defaults
        terminalSettings = TerminalSettingsSync(storage: store.storage, settings: terminal)
        preferences = CloudSyncPreferences(defaults: defaults)
        observers.append(NotificationCenter.default.addObserver(
            forName: CloudSync.statusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let status = note.object as? CloudSync.Status else { return }
            MainActor.assumeIsolated { self?.status = status }
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
        let preferences = preferences
        Task { await CloudSync.shared.apply(preferences) }
    }

    public func syncNow() {
        Task { await CloudSync.shared.syncNow() }
    }

    /// What to say under the switch.
    public var statusText: String {
        switch status {
        case .off: return "Off"
        case .unavailable: return "This build is not signed for iCloud."
        case .syncing: return "Syncing…"
        case let .idle(lastSync?): return "Synced \(lastSync.formatted(.relative(presentation: .named)))"
        case .idle(nil): return "Up to date"
        case let .failed(message): return message
        }
    }
}
