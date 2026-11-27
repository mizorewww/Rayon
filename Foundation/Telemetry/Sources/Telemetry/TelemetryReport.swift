//
//  TelemetryReport.swift
//  Telemetry
//
//  The only thing Rayon ever sends: enums, Bools and bucketed integers,
//  never a String. docs/telemetry.md §4.2 is the allow-list; a field added
//  here changes the schema snapshot test and needs the same review.
//

import Foundation

public struct TelemetryReport: Codable, Equatable, Sendable {
    /// Bumped whenever a field is added or changes meaning.
    public static let currentSchema = 1

    public var schema = Self.currentSchema
    /// Random per report, so the server can drop a retried duplicate.
    public var nonce = UUID()
    public var level: TelemetryLevel
    public var appVersion: Version
    public var channel: Channel
    public var platform: Platform
    public var osVersion: Version
    public var deviceClass: DeviceClass
    public var language: Language
    public var regionGroup: RegionGroup
    /// Level 1 and up: crashes and hangs from MetricKit, scrubbed.
    public var diagnostics: [Diagnostic] = []
    /// Level 2 and up: one day's feature counts.
    public var usage: Usage?
    /// Level 3, on sampled days only.
    public var detail: Detail?

    public init(level: TelemetryLevel, environment: TelemetryEnvironment) {
        self.level = level
        appVersion = environment.appVersion
        channel = environment.channel
        platform = environment.platform
        osVersion = environment.osVersion
        deviceClass = environment.deviceClass
        language = environment.language
        regionGroup = environment.regionGroup
    }
}

public extension TelemetryReport {
    enum Channel: String, Codable, CaseIterable, Sendable {
        case appStore, direct, testFlight, debug
    }

    enum Platform: String, Codable, CaseIterable, Sendable {
        case macOS, iOS, iPadOS
    }

    enum DeviceClass: String, Codable, CaseIterable, Sendable {
        case macAppleSilicon = "mac-appleSilicon"
        case macIntel = "mac-intel"
        case iPhone, iPad
    }

    enum Language: String, Codable, CaseIterable, Sendable {
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"
        case other
    }

    enum RegionGroup: String, Codable, CaseIterable, Sendable {
        /// The EEA, the UK and Switzerland: nothing is sent until the person chooses.
        case eea = "EEA"
        case cn = "CN"
        case other
    }

    /// A version cut to numbers: "5.2.0" for the app, "15.4" for the OS.
    struct Version: Codable, Hashable, Sendable, CustomStringConvertible {
        public let major: Int
        public let minor: Int
        public let patch: Int?

        public init(major: Int, minor: Int, patch: Int? = nil) {
            self.major = min(max(major, 0), 999)
            self.minor = min(max(minor, 0), 999)
            self.patch = patch.map { min(max($0, 0), 999) }
        }

        /// The first two or three dot-separated numbers in `text`, if it starts with them.
        public init?(parsing text: String, keepPatch: Bool) {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false).prefix(3).map { Int($0) }
            guard parts.count >= 2, let major = parts[0], let minor = parts[1] else {
                guard parts.count == 1, let major = parts[0] else { return nil }
                self.init(major: major, minor: 0, patch: keepPatch ? 0 : nil)
                return
            }
            let patch = parts.count == 3 ? parts[2] : nil
            self.init(major: major, minor: minor, patch: keepPatch ? (patch ?? 0) : nil)
        }

        public var description: String {
            patch.map { "\(major).\(minor).\($0)" } ?? "\(major).\(minor)"
        }

        public init(from decoder: Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let version = Version(parsing: text, keepPatch: text.split(separator: ".").count == 3) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a version"))
            }
            self = version
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }
    }
}
