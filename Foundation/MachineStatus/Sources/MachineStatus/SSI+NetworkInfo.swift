//
//  SSI+NetworkInfo.swift
//
//
//  Created by Lakr Aream on 2022/3/2.
//

import Foundation

public extension ServerStatus {
    /// 服务器 NET 信息
    struct NetworkInfo: Codable, Equatable, Hashable, Sendable {
        public let elements: [NetworkInfoElement]

        public struct NetworkInfoElement: Codable, Equatable, Hashable, Identifiable, Sendable {
            /// Stable across refreshes: the parser keeps one row per device.
            public var id: String { device }

            public let device: String
            public let rxBytesPerSec: Int
            public let txBytesPerSec: Int

            public init(device: String, rxBytesPerSec: Int, txBytesPerSec: Int) {
                self.device = device
                self.rxBytesPerSec = rxBytesPerSec
                self.txBytesPerSec = txBytesPerSec
            }

            public func description() -> String {
                """
                interface: \(device)
                rxBytes: \(rxBytesPerSec)/s txBytes: \(txBytesPerSec)/s
                """
            }
        }

        public init() {
            elements = []
        }

        public init(elements: [NetworkInfoElement]) {
            self.elements = elements
        }

        /// Rates between two counter readings `interval` seconds apart. An
        /// interface whose counters went back (reset or re-created) is left
        /// out for the round.
        init(before: [String: ProcParsers.NetworkCounters], after: [String: ProcParsers.NetworkCounters], interval: Double) {
            let elements = after.compactMap { device, now -> NetworkInfoElement? in
                guard interval > 0, let then = before[device], now.rx >= then.rx, now.tx >= then.tx else {
                    return nil
                }
                return NetworkInfoElement(
                    device: device,
                    rxBytesPerSec: Int((Double(now.rx - then.rx) / interval).rounded()),
                    txBytesPerSec: Int((Double(now.tx - then.tx) / interval).rounded())
                )
            }
            self.init(elements: elements.sorted { $0.device < $1.device })
        }
    }
}
