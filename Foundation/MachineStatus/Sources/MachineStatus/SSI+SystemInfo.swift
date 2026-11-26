//
//  SSI+SystemInfo.swift
//
//
//  Created by Lakr Aream on 2022/3/2.
//

import Foundation

public extension ServerStatus {
    /// 服务器 系统 信息
    struct SystemInfo: Codable, Equatable, Hashable, Sendable {
        public let releaseName: String
        public let uptimeSec: Double
        public let hostname: String
        public let runningProcs: Int
        public let totalProcs: Int
        public let load1: Float
        public let load5: Float
        public let load15: Float
        public init() {
            releaseName = ""
            uptimeSec = 0
            hostname = ""
            runningProcs = 0
            totalProcs = 0
            load1 = 0
            load5 = 0
            load15 = 0
        }

        public init(release: String,
                    uptimeInSec: Double, hostname: String,
                    runningProcs: Int, totalProcs: Int,
                    load1: Float, load5: Float, load15: Float)
        {
            releaseName = release
            uptimeSec = uptimeInSec
            self.hostname = hostname
            self.runningProcs = runningProcs
            self.totalProcs = totalProcs
            self.load1 = load1
            self.load5 = load5
            self.load15 = load15
        }

        public func description() -> String {
            """
            release: \(releaseName)
            uptime: \(uptimeSec) second
            hostname: \(hostname)
            running process: \(runningProcs) total: \(totalProcs)
            load1: \(load1) load5: \(load5) load15: \(load15)
            """
        }
    }

    struct SystemLoadInternal: Codable, Equatable, Hashable, Sendable {
        public var runningProcess: Int = 0
        public var totalProcess: Int = 0
        public var load1avg: Float = 0
        public var load5avg: Float = 0
        public var load15avg: Float = 0
    }
}
