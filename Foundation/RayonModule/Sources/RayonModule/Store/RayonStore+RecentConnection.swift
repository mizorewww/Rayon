//
//  RayonStore+RecentConnection.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/1.
//

import Foundation
import Logger

public extension RayonStore {
    enum RecentConnection: Codable, Equatable, Identifiable, Sendable {
        case command(command: SSHCommandReader)
        case machine(machine: RDMachine.ID)

        public var id: String {
            switch self {
            case let .command(command): command.command
            case let .machine(machine): machine.uuidString
            }
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }

        init?(record: RecentConnectionRecord) {
            if let machine = record.machine {
                self = .machine(machine: machine)
            } else if let command = record.command {
                self = .command(command: command)
            } else {
                return nil
            }
        }

        func record(at position: Int) -> RecentConnectionRecord {
            switch self {
            case let .command(command):
                RecentConnectionRecord(id: id, command: command, position: position)
            case let .machine(machine):
                RecentConnectionRecord(id: id, machine: machine, position: position)
            }
        }

        @MainActor
        public var equivalentSSHCommand: String {
            switch self {
            case let .command(command):
                return command.command
            case let .machine(machineID):
                guard let machine = RayonStore.shared.machine(machineID),
                      let identity = RayonStore.shared.associatedIdentity(for: machine)
                else {
                    return ""
                }
                let username = machine.sshLoginUsername(identity: identity)
                let proxy = machine.transport == .cloudflareAccess ? SSHCommandReader.cloudflareProxyOption + " " : ""
                return "ssh \(proxy)\(username)@\(machine.remoteAddress) -p \(machine.remotePort)"
            }
        }
    }

    internal func persistRecent() {
        do {
            try storage.saveRecentConnections(recentRecord.enumerated().map { $1.record(at: $0) })
        } catch {
            Logger.database.errorFile("saving the recent connections failed: \(error.localizedDescription)")
        }
    }

    func cleanRecentIfNeeded() {
        let build = recentRecord.filter { record in
            switch record {
            case .command: true
            case let .machine(machine): self.machine(machine) != nil
            }
        }
        if build != recentRecord { recentRecord = build }
    }

    func storeRecentIfNeeded(from recent: RecentConnection) {
        guard storeRecent, !recentRecord.contains(recent) else { return }
        var records = recentRecord
        records.insert(recent, at: 0)
        if records.count > maxRecentRecordCount {
            records.removeLast(records.count - maxRecentRecordCount)
        }
        recentRecord = records
    }

    func storeRecentIfNeeded(from machine: RDMachine.ID) {
        storeRecentIfNeeded(from: .machine(machine: machine))
    }

    /// Quick Connect commands are kept only while "Record command" is on.
    func storeRecentIfNeeded(from command: SSHCommandReader) {
        guard saveTemporarySession else { return }
        storeRecentIfNeeded(from: .command(command: command))
    }
}
