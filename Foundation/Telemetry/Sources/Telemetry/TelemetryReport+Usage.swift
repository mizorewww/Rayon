//
//  TelemetryReport+Usage.swift
//  Telemetry
//
//  Level 2: one day's feature counts and the state of a few settings.
//

import Foundation

public extension TelemetryReport {
    struct Usage: Codable, Equatable, Sendable {
        public var counts: [Feature: CountBucket]
        public var portForwardsStarted: [PortForwardKind: CountBucket]
        public var connectionOutcome: [ConnectionOutcome: CountBucket]
        public var authMethodUsed: [AuthMethod: Bool]
        public var keyTypes: [KeyType: Bool]
        public var savedHosts: CountBucket
        public var identities: CountBucket
        public var iCloudSyncEnabled: Bool
        public var customTheme: Bool
        public var redactionMode: RedactionMode
        /// Days the app was used in the last 28, from a set that stays on the device.
        public var activeDaysLast28: CountBucket
    }

    enum Feature: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case terminalSessionsOpened, sftpBrowsed, fileTransfers, editorOpened
        case monitorOpened, vncSessions, uuRemoteSessions, snippetsRun
    }

    enum PortForwardKind: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case local, remote, dynamic
    }

    enum ConnectionOutcome: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case success, authFailed, timeout, refused, hostKeyMismatch, dnsFailed, other
    }

    enum AuthMethod: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case password, publicKey, agent, keyboardInteractive
    }

    enum KeyType: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case ed25519, ecdsa, rsa
    }

    enum RedactionMode: String, Codable, CaseIterable, Sendable {
        case none, address, all
    }
}

/// What the app knows about its own state when a day's report is made.
public struct TelemetrySnapshot: Sendable {
    public var savedHosts: Int
    public var identities: Int
    public var keyTypes: Set<TelemetryReport.KeyType>
    public var iCloudSyncEnabled: Bool
    public var customTheme: Bool
    public var redactionMode: TelemetryReport.RedactionMode

    public init(
        savedHosts: Int,
        identities: Int,
        keyTypes: Set<TelemetryReport.KeyType>,
        iCloudSyncEnabled: Bool,
        customTheme: Bool,
        redactionMode: TelemetryReport.RedactionMode
    ) {
        self.savedHosts = savedHosts
        self.identities = identities
        self.keyTypes = keyTypes
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.customTheme = customTheme
        self.redactionMode = redactionMode
    }

    public static let empty = TelemetrySnapshot(savedHosts: 0, identities: 0, keyTypes: [], iCloudSyncEnabled: false, customTheme: false, redactionMode: .none)
}

extension Dictionary where Value == CountBucket, Key: CaseIterable {
    /// Every case, bucketed, so the report always has the same shape.
    static func bucketed(_ counts: [Key: Int]) -> Self {
        Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0, CountBucket(counts[$0] ?? 0)) })
    }
}

extension Dictionary where Value == Bool, Key: CaseIterable {
    static func flags(_ set: Set<Key>) -> Self {
        Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0, set.contains($0)) })
    }
}
