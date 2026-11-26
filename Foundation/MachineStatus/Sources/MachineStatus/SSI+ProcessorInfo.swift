//
//  SSI+ProcessorInfo.swift
//
//
//  Created by Lakr Aream on 2022/3/2.
//

import Foundation

public extension ServerStatus {
    /// 服务器 CPU 信息
    struct ProcessorInfo: Codable, Equatable, Sendable {
        public var summary: ProcessPercentInfo
        public var cores: [ProcessPercentInfo]
        public init() {
            summary = ProcessPercentInfo()
            cores = []
        }

        public init(summary: ProcessPercentInfo,
                    cores: [String: ProcessPercentInfo])
        {
            self.summary = summary
            let keys = cores
                .keys
                .sorted(by: { a, b in
                    if a.count < 3 || b.count < 3 {
                        return a < b
                    }
                    if let droppedA = Int(a.dropFirst(3)),
                       let droppedB = Int(b.dropFirst(3))
                    {
                        return droppedA < droppedB
                    } else {
                        return a < b
                    }
                })
            var build: [ProcessPercentInfo] = []
            for key in keys {
                guard var core = cores[key] else {
                    continue
                }
                core.name = key
                build.append(core)
            }
            self.cores = build
        }

        /// Builds from two `/proc/stat` readings; nil when either is
        /// missing the aggregate cpu row.
        init?(before: ProcParsers.ProcStat, after: ProcParsers.ProcStat) {
            guard let beforeSummary = before.summary, let afterSummary = after.summary else {
                return nil
            }
            var cores = [String: ProcessPercentInfo]()
            for (key, then) in before.cores {
                guard let now = after.cores[key] else { continue }
                cores[key] = ProcParsers.calculatePercent(priv: then, curr: now)
            }
            self.init(summary: ProcParsers.calculatePercent(priv: beforeSummary, curr: afterSummary), cores: cores)
        }
    }

    /// 服务器 CPU 信息 这里全部是百分比
    struct ProcessPercentInfo: Codable, Equatable, Identifiable, Sendable {
        /// Stable across refreshes: the kernel names cores cpu0…cpuN.
        public var id: String { name }

        public var name: String

        public var sumSystem: Float
        public var sumUser: Float
        public var sumIOWait: Float
        public var sumNice: Float
        public var sumUsed: Float
        public init() {
            name = ""
            sumSystem = 0
            sumUser = 0
            sumIOWait = 0
            sumNice = 0
            sumUsed = 0
        }

        public init(
            system: Float, user: Float,
            iowait: Float, nice: Float,
            sum: Float
        ) {
            name = ""
            sumSystem = system
            sumUser = user
            sumIOWait = iowait
            sumNice = nice
            sumUsed = sum
        }

        public func description() -> String {
            "system: \(sumSystem), user: \(sumUser), iowait: \(sumIOWait), nice: \(sumNice)"
        }
    }

    /// One row of `/proc/stat`, in jiffies since boot. 64-bit because a
    /// many-core server passes 2^24 idle jiffies within hours, where a
    /// `Float` stops resolving a second's increment. `guest` and
    /// `guest_nice` are left out on purpose: the kernel already counts
    /// them inside `user` and `nice`.
    struct ProcessInfoElement: Codable, Equatable, Sendable {
        public let user: UInt64
        public let nice: UInt64
        public let system: UInt64
        public let idle: UInt64
        public let iowait: UInt64
        public let irq: UInt64
        public let softIrq: UInt64
        public let steal: UInt64

        public init(user: UInt64, nice: UInt64, system: UInt64, idle: UInt64, iowait: UInt64 = 0, irq: UInt64 = 0, softIrq: UInt64 = 0, steal: UInt64 = 0) {
            self.user = user
            self.nice = nice
            self.system = system
            self.idle = idle
            self.iowait = iowait
            self.irq = irq
            self.softIrq = softIrq
            self.steal = steal
        }

        var total: UInt64 {
            user + nice + system + idle + iowait + irq + softIrq + steal
        }
    }
}
