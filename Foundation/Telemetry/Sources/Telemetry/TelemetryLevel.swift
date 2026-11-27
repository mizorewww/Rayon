//
//  TelemetryLevel.swift
//  Telemetry
//

import Foundation

/// How much this device shares; the settings slider's four stops.
public enum TelemetryLevel: Int, Codable, CaseIterable, Comparable, Sendable {
    case off = 0
    case crashReports = 1
    case usage = 2
    case detailed = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .crashReports: "Crash Reports"
        case .usage: "Crash Reports and Usage"
        case .detailed: "Detailed Diagnostics"
        }
    }

    public var summary: String {
        switch self {
        case .off: "Nothing is sent."
        case .crashReports: "Crash and hang reports, without your hosts, names or terminal content."
        case .usage: "Also a daily count of which features are used. No identifier, no IP address kept."
        case .detailed: "Also performance timings and protocol details, on some days."
        }
    }
}
