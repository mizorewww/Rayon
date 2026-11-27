//
//  TelemetryReport+Detail.swift
//  Telemetry
//
//  Level 3, on one day in ten: MetricKit's daily metrics re-bucketed, how
//  long sign-ins took and which OS family the monitored servers run.
//

import Foundation

public extension TelemetryReport {
    struct Detail: Codable, Equatable, Sendable {
        public var connectLatency: [LatencyBucket: CountBucket]
        public var remoteOSFamily: [RemoteOSFamily: CountBucket]
        /// The last day's MetricKit metrics, when one arrived that day.
        public var metrics: Metrics?
    }

    /// The time from opening a connection to being signed in.
    enum LatencyBucket: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case under100ms, under300ms, under1s, under3s, over3s

        public init(_ duration: Duration) {
            let milliseconds = duration / .milliseconds(1)
            self = switch milliseconds {
            case ..<100: .under100ms
            case ..<300: .under300ms
            case ..<1000: .under1s
            case ..<3000: .under3s
            default: .over3s
            }
        }
    }

    enum RemoteOSFamily: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
        case linux, darwin, bsd, other

        /// From `uname -s`, which never leaves the device itself.
        public init(unameKernel name: String) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self = if name == "linux" {
                .linux
            } else if name == "darwin" {
                .darwin
            } else if name.hasSuffix("bsd") || name == "dragonfly" {
                .bsd
            } else {
                .other
            }
        }
    }

    /// MetricKit's day, each value rounded down to the lower bound of a fixed step.
    struct Metrics: Codable, Equatable, Sendable {
        /// Median time to first draw, in milliseconds.
        public var launchTime: Int?
        /// Total hang time over the day, in milliseconds.
        public var hangTime: Int?
        /// In megabytes.
        public var peakMemory: Int?
        /// In seconds.
        public var cpuTime: Int?
        /// Logical writes, in megabytes.
        public var diskWrites: Int?

        static let millisecondSteps = [0, 100, 300, 1000, 3000, 10000, 30000]
        static let megabyteSteps = [0, 50, 100, 250, 500, 1000, 2000, 4000, 8000]
        static let secondSteps = [0, 10, 60, 300, 1800, 3600, 14400]

        public init(launchMilliseconds: Double?, hangMilliseconds: Double?, peakMemoryMegabytes: Double?, cpuSeconds: Double?, diskWriteMegabytes: Double?) {
            launchTime = launchMilliseconds.map { Self.floor($0, to: Self.millisecondSteps) }
            hangTime = hangMilliseconds.map { Self.floor($0, to: Self.millisecondSteps) }
            peakMemory = peakMemoryMegabytes.map { Self.floor($0, to: Self.megabyteSteps) }
            cpuTime = cpuSeconds.map { Self.floor($0, to: Self.secondSteps) }
            diskWrites = diskWriteMegabytes.map { Self.floor($0, to: Self.megabyteSteps) }
        }

        static func floor(_ value: Double, to steps: [Int]) -> Int {
            steps.last { Double($0) <= value } ?? 0
        }
    }
}
