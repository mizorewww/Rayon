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
        case .off: String(localized: "Off", bundle: .module)
        case .crashReports: String(localized: "Crash Reports", bundle: .module)
        case .usage: String(localized: "Crash Reports and Usage", bundle: .module)
        case .detailed: String(localized: "Detailed Diagnostics", bundle: .module)
        }
    }

    public var summary: String {
        switch self {
        case .off: String(localized: "Nothing is sent.", bundle: .module)
        case .crashReports: String(localized: "Crash and hang reports, without your hosts, names or terminal content.", bundle: .module)
        case .usage: String(localized: "Also a daily count of which features are used. No identifier, no IP address kept.", bundle: .module)
        case .detailed: String(localized: "Also performance timings and protocol details, on some days.", bundle: .module)
        }
    }
}
