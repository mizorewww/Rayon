//
//  TelemetryEnvironment.swift
//  Telemetry
//
//  The coarse facts every report carries, read once per launch.
//

import Foundation
import StoreKit
#if canImport(UIKit)
    import UIKit
#endif

public struct TelemetryEnvironment: Equatable, Sendable {
    public var appVersion: TelemetryReport.Version
    public var channel: TelemetryReport.Channel
    public var platform: TelemetryReport.Platform
    public var osVersion: TelemetryReport.Version
    public var deviceClass: TelemetryReport.DeviceClass
    public var language: TelemetryReport.Language
    public var region: Region

    public var regionGroup: TelemetryReport.RegionGroup { region.group }

    /// Where the person is, as far as consent goes.
    public enum Region: Equatable, Sendable {
        /// The EEA, the UK or Switzerland, or a region that could not be told:
        /// nothing is sent until the person chooses.
        case strict
        /// Mainland China: nothing is sent until the notice is dismissed.
        case china
        case other

        var group: TelemetryReport.RegionGroup {
            switch self {
            case .strict: .eea
            case .china: .cn
            case .other: .other
            }
        }

        /// ISO 3166-1 alpha-2 and alpha-3 codes of the EEA, the UK and Switzerland.
        static let strictCountries: Set<String> = [
            "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
            "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "GB", "CH",
            "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
            "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE", "ISL", "LIE", "NOR", "GBR", "CHE",
        ]

        public init(countryCode: String?) {
            guard let code = countryCode?.uppercased(), code.count == 2 || code.count == 3, code.allSatisfy(\.isLetter) else {
                self = .strict
                return
            }
            self = if Self.strictCountries.contains(code) {
                .strict
            } else if code == "CN" || code == "CHN" {
                .china
            } else {
                .other
            }
        }

        /// The App Store storefront, else the system's region, else strict.
        public static func detect() async -> Region {
            let storefront = await withTaskGroup(of: String?.self) { group in
                group.addTask { await Storefront.current?.countryCode }
                // StoreKit can take long to answer offline; the locale is good enough then.
                group.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            return Region(countryCode: storefront ?? Locale.current.region?.identifier)
        }
    }

    @MainActor public static func current(region: Region) async -> TelemetryEnvironment {
        let info = Bundle.main.infoDictionary
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let language: TelemetryReport.Language = switch Bundle.main.preferredLocalizations.first {
        case "en": .en
        case "zh-Hans": .zhHans
        case "zh-Hant": .zhHant
        default: .other
        }
        #if os(macOS)
            #if arch(arm64)
                let device = TelemetryReport.DeviceClass.macAppleSilicon
            #else
                let device = TelemetryReport.DeviceClass.macIntel
            #endif
            let platform = TelemetryReport.Platform.macOS
        #else
            let pad = UIDevice.current.userInterfaceIdiom == .pad
            let device: TelemetryReport.DeviceClass = pad ? .iPad : .iPhone
            let platform: TelemetryReport.Platform = pad ? .iPadOS : .iOS
        #endif
        return TelemetryEnvironment(
            appVersion: (info?["CFBundleShortVersionString"] as? String).flatMap { .init(parsing: $0, keepPatch: true) } ?? .init(major: 0, minor: 0, patch: 0),
            channel: await channel(),
            platform: platform,
            osVersion: .init(major: system.majorVersion, minor: system.minorVersion),
            deviceClass: device,
            language: language,
            region: region
        )
    }

    private static func channel() async -> TelemetryReport.Channel {
        #if DEBUG
            return .debug
        #elseif os(macOS)
            // The Mac app ships as a notarized disk image (UpdateManager's GitHub channel).
            return .direct
        #else
            guard case let .verified(transaction)? = try? await AppTransaction.shared else { return .appStore }
            return transaction.environment == .sandbox ? .testFlight : .appStore
        #endif
    }
}
