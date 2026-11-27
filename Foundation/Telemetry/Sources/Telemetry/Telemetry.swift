//
//  Telemetry.swift
//  Telemetry
//
//  The level this device chose, and what follows from it. The level is
//  stored in this device's defaults only, never synced or backed up:
//  consent belongs to the device and the storefront it was given in.
//

import Foundation
import MetricKit
import Observation

@MainActor @Observable
public final class Telemetry {
    public static let shared = Telemetry()

    static let levelKey = "telemetry.level"
    static let noticeKey = "telemetry.noticeShown"

    /// Counting happens wherever an event does; the collector is not tied to the main actor.
    nonisolated static let collector = TelemetryCollector(root: TelemetryCollector.defaultRoot, sender: TelemetrySender())

    /// What the person picked; nil until they do.
    public private(set) var choice: TelemetryLevel?
    /// Nil until the storefront is known.
    public private(set) var region: TelemetryEnvironment.Region?
    public private(set) var noticeShown: Bool
    /// The app's own state for the daily report; set once at launch.
    public var snapshot: @MainActor () -> TelemetrySnapshot = { .empty }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var subscriber: TelemetrySubscriber?
    @ObservationIgnored private var dayObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = (defaults.object(forKey: Self.levelKey) as? Int).flatMap(TelemetryLevel.init(rawValue:))
        noticeShown = defaults.bool(forKey: Self.noticeKey)
    }

    /// The level in force. Without a choice: off in the EEA, the UK,
    /// Switzerland or an unknown region; off in China until the notice is
    /// dismissed; level 2 elsewhere.
    public var level: TelemetryLevel {
        if let choice { return choice }
        switch region {
        case nil, .strict?: return .off
        case .china?: return noticeShown ? .usage : .off
        case .other?: return .usage
        }
    }

    /// The EEA, UK and CH variant: two equal choices and nothing preselected.
    public var asksForConsent: Bool { region == .strict }

    /// Shown once, inline, after the region is known.
    public var showsNotice: Bool { region != nil && !noticeShown }

    /// Debug builds, preview runs and a build without a real endpoint queue
    /// reports but never send them.
    public nonisolated static var sendingAllowed: Bool {
        #if DEBUG
            return false
        #else
            let preview = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RAYON_PREVIEW_") }
            return TelemetryEndpoint.isConfigured && !preview
        #endif
    }

    public func start() {
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Telemetry.shared.wake() }
        }
        Task {
            let region = await TelemetryEnvironment.Region.detect()
            let environment = await TelemetryEnvironment.current(region: region)
            self.region = region
            await Self.collector.configure(environment: environment, snapshot: snapshot(), level: level)
            applySubscription()
            wake()
        }
    }

    /// At launch, on coming to the foreground and when the day changes:
    /// finishes a past day's report and sends what is queued.
    public func wake() {
        guard region != nil else { return }
        let snapshot = snapshot()
        Task {
            await Self.collector.rollOver(snapshot: snapshot)
            await Self.collector.flush(allowed: Self.sendingAllowed)
        }
    }

    public func setLevel(_ newLevel: TelemetryLevel) {
        choice = newLevel
        defaults.set(newLevel.rawValue, forKey: Self.levelKey)
        markNoticeShown()
        applySubscription()
        Task {
            await Self.collector.setLevel(newLevel)
            await Self.collector.rollOver(snapshot: snapshot())
        }
    }

    /// The notice's "OK" and "Settings…": the default stands.
    public func markNoticeShown() {
        guard !noticeShown else { return }
        noticeShown = true
        defaults.set(true, forKey: Self.noticeKey)
        if choice == nil { setCollectorLevel() }
    }

    private func setCollectorLevel() {
        let level = level
        applySubscription()
        Task { await Self.collector.setLevel(level) }
    }

    /// Level 0 removes the MetricKit subscriber; anything above adds it.
    private func applySubscription() {
        if level > .off, subscriber == nil {
            let collector = Self.collector
            let subscriber = TelemetrySubscriber(
                diagnostics: { items in
                    Task {
                        await collector.recordDiagnostics(items)
                        await collector.flush(allowed: Telemetry.sendingAllowed)
                    }
                },
                metrics: { metrics in Task { await collector.recordMetrics(metrics) } }
            )
            MXMetricManager.shared.add(subscriber)
            self.subscriber = subscriber
        } else if level == .off, let subscriber {
            MXMetricManager.shared.remove(subscriber)
            self.subscriber = nil
        }
    }

    // MARK: - Counting

    public nonisolated static func record(_ event: TelemetryEvent) {
        Task { await collector.record(event) }
    }

    // MARK: - What's sent

    public func pendingReports() async -> [TelemetryReport] {
        await Self.collector.pending()
    }

    public func lastSentReport() async -> TelemetryReport? {
        await Self.collector.lastSent()
    }

    public func deletePendingReports() async {
        await Self.collector.deletePending()
    }

    /// Forgets the days the app was used, which only ever leave the device as a count.
    public func resetActivityHistory() async {
        await Self.collector.resetActiveDays()
    }

    /// Pretty JSON, as it is sent.
    public static func json(_ reports: [TelemetryReport]) -> String {
        (try? TelemetryQueue.prettyEncoder().encode(reports)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
