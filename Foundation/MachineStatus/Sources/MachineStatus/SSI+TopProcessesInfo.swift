//
//  SSI+TopProcessesInfo.swift
//  MachineStatus
//

import Foundation

public extension ServerStatus {
    /// The busiest processes on the server, read from `ps` each refresh:
    /// one list by CPU and one by resident memory.
    struct TopProcessesInfo: Codable, Equatable, Sendable {
        public let byCPU: [TopProcess]
        public let byMemory: [TopProcess]

        public init(byCPU: [TopProcess] = [], byMemory: [TopProcess] = []) {
            self.byCPU = byCPU
            self.byMemory = byMemory
        }

        /// Reads the `procs-cpu` and `procs-mem` sections. A system whose
        /// `ps` cannot sort (busybox) only fills `procs-cpu` with plain `ps`
        /// output; both lists are then ordered from that one reading.
        init(cpuSection: String, memorySection: String) {
            let byCPU = ProcParsers.parseProcessList(cpuSection, order: .cpu)
            var byMemory = ProcParsers.parseProcessList(memorySection, order: .memory)
            if byMemory.isEmpty {
                byMemory = ProcParsers.parseProcessList(cpuSection, order: .memory)
            }
            self.init(byCPU: byCPU, byMemory: byMemory)
        }
    }

    /// One row of `ps`. Columns a system's `ps` does not have stay nil:
    /// busybox reports no CPU or memory share.
    struct TopProcess: Codable, Equatable, Identifiable, Sendable {
        /// Unique within one reading.
        public var id: Int { pid }

        public let pid: Int
        public let user: String
        /// The program's name: Linux's `comm`, or the last part of the
        /// executable's path on macOS and busybox.
        public let command: String
        /// Share of one core, so it can pass 100 on a multi-core server.
        public let cpuPercent: Double?
        public let memoryPercent: Double?
        public let residentKB: Double?

        public init(pid: Int, user: String, command: String, cpuPercent: Double? = nil, memoryPercent: Double? = nil, residentKB: Double? = nil) {
            self.pid = pid
            self.user = user
            self.command = command
            self.cpuPercent = cpuPercent
            self.memoryPercent = memoryPercent
            self.residentKB = residentKB
        }
    }
}
