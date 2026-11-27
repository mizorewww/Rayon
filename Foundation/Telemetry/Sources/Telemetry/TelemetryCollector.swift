//
//  TelemetryCollector.swift
//  Telemetry
//
//  Adds up the day's events on the device, turns a finished day into one
//  report, keeps the queue and sends it. Everything it stores lives in
//  Application Support/Telemetry.
//

import Foundation
import Logger

/// Something worth counting; enums only, so nothing about a server can ride along.
public enum TelemetryEvent: Sendable {
    case feature(TelemetryReport.Feature)
    case portForwardStarted(TelemetryReport.PortForwardKind)
    case connection(TelemetryReport.ConnectionOutcome, auth: TelemetryReport.AuthMethod?)
    case connectLatency(Duration)
    case remoteOS(TelemetryReport.RemoteOSFamily)
}

actor TelemetryCollector {
    /// One day's raw counts. They never leave the device; only buckets do.
    struct Day: Codable, Equatable {
        var day: Int
        /// The level-3 coin flip for this day.
        var detailed: Bool
        var features: [TelemetryReport.Feature: Int] = [:]
        var portForwards: [TelemetryReport.PortForwardKind: Int] = [:]
        var outcomes: [TelemetryReport.ConnectionOutcome: Int] = [:]
        var authMethods: Set<TelemetryReport.AuthMethod> = []
        var latency: [TelemetryReport.LatencyBucket: Int] = [:]
        var remoteOS: [TelemetryReport.RemoteOSFamily: Int] = [:]
        var metrics: TelemetryReport.Metrics?

    }

    static let detailedSampleRate = 0.1
    static let batchSize = 10

    let queue: TelemetryQueue
    private let dayFile: URL
    private let activeDaysFile: URL
    private let sender: TelemetrySender
    private let now: @Sendable () -> Date
    private let coinFlip: @Sendable () -> Bool

    private(set) var level: TelemetryLevel = .off
    private var environment: TelemetryEnvironment?
    private var snapshot = TelemetrySnapshot.empty
    private var current: Day?
    private var activeDays: Set<Int>?
    private var sending = false
    private var failures = 0
    private var retry: Task<Void, Never>?

    init(
        root: URL,
        sender: TelemetrySender,
        now: @escaping @Sendable () -> Date = Date.init,
        coinFlip: @escaping @Sendable () -> Bool = { Double.random(in: 0 ..< 1) < TelemetryCollector.detailedSampleRate }
    ) {
        queue = TelemetryQueue(root: root)
        dayFile = root.appending(path: "today.json")
        activeDaysFile = root.appending(path: "active-days.json")
        self.sender = sender
        self.now = now
        self.coinFlip = coinFlip
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Telemetry", directoryHint: .isDirectory)
    }

    // MARK: - State

    func configure(environment: TelemetryEnvironment, snapshot: TelemetrySnapshot, level: TelemetryLevel) {
        self.environment = environment
        self.snapshot = snapshot
        setLevel(level)
    }

    /// Applies at once: lowering drops what the new level would not send.
    func setLevel(_ newLevel: TelemetryLevel) {
        let old = level
        level = newLevel
        guard newLevel < old else { return }
        retry?.cancel()
        queue.trim(to: newLevel)
        if newLevel < .usage {
            current = nil
            try? FileManager.default.removeItem(at: dayFile)
        } else if newLevel < .detailed, var day = loadDay() {
            day.latency = [:]
            day.remoteOS = [:]
            day.metrics = nil
            save(day)
        }
    }

    func record(_ event: TelemetryEvent) {
        guard level >= .usage else { return }
        var day = today()
        switch event {
        case let .feature(feature):
            day.features[feature, default: 0] += 1
        case let .portForwardStarted(kind):
            day.portForwards[kind, default: 0] += 1
        case let .connection(outcome, auth):
            day.outcomes[outcome, default: 0] += 1
            if let auth { day.authMethods.insert(auth) }
        case let .connectLatency(duration):
            guard level == .detailed, day.detailed else { return }
            day.latency[.init(duration), default: 0] += 1
        case let .remoteOS(family):
            guard level == .detailed, day.detailed else { return }
            day.remoteOS[family, default: 0] += 1
        }
        save(day)
    }

    func recordMetrics(_ metrics: TelemetryReport.Metrics) {
        guard level == .detailed else { return }
        var day = today()
        guard day.detailed else { return }
        day.metrics = metrics
        save(day)
    }

    /// Queues one report for the crashes and hangs MetricKit delivered.
    func recordDiagnostics(_ diagnostics: [TelemetryReport.Diagnostic]) {
        guard level >= .crashReports, !diagnostics.isEmpty, let environment else { return }
        var report = TelemetryReport(level: level, environment: environment)
        report.diagnostics = diagnostics
        enqueue(report)
    }

    /// Notes today as a day the app was used and turns a finished day into a report.
    /// A finished day is described by the snapshot taken while it ran.
    func rollOver(snapshot: TelemetrySnapshot) {
        defer { self.snapshot = snapshot }
        guard level >= .usage else { return }
        _ = today()
        var days = loadActiveDays()
        if days.insert(dayNumber()).inserted {
            activeDays = days.filter { $0 > dayNumber() - 28 }
            try? JSONEncoder().encode(activeDays).write(to: activeDaysFile, options: .atomic)
        }
    }

    func resetActiveDays() {
        activeDays = []
        try? FileManager.default.removeItem(at: activeDaysFile)
    }

    // MARK: - Days

    private func dayNumber() -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: calendar.startOfDay(for: now())).day ?? 0
    }

    /// Today's counts; a stored earlier day is reported first.
    private func today() -> Day {
        let number = dayNumber()
        let stored = current ?? loadDay()
        if let stored, stored.day == number {
            current = stored
            return stored
        }
        // A day exists only when the app ran at level 2 or up on it.
        if let stored, let report = report(for: stored) {
            enqueue(report)
        }
        let day = Day(day: number, detailed: coinFlip())
        save(day)
        return day
    }

    private func report(for day: Day) -> TelemetryReport? {
        guard let environment else { return nil }
        var report = TelemetryReport(level: level, environment: environment)
        let activeCount = loadActiveDays().filter { $0 > day.day - 28 && $0 <= day.day }.count
        report.usage = TelemetryReport.Usage(
            counts: .bucketed(day.features),
            portForwardsStarted: .bucketed(day.portForwards),
            connectionOutcome: .bucketed(day.outcomes),
            authMethodUsed: .flags(day.authMethods),
            keyTypes: .flags(snapshot.keyTypes),
            savedHosts: CountBucket(snapshot.savedHosts),
            identities: CountBucket(snapshot.identities),
            iCloudSyncEnabled: snapshot.iCloudSyncEnabled,
            customTheme: snapshot.customTheme,
            redactionMode: snapshot.redactionMode,
            activeDaysLast28: CountBucket(activeCount)
        )
        if level == .detailed, day.detailed {
            report.detail = TelemetryReport.Detail(
                connectLatency: .bucketed(day.latency),
                remoteOSFamily: .bucketed(day.remoteOS),
                metrics: day.metrics
            )
        }
        return report
    }

    private func loadDay() -> Day? {
        (try? Data(contentsOf: dayFile)).flatMap { try? JSONDecoder().decode(Day.self, from: $0) }
    }

    private func save(_ day: Day) {
        current = day
        try? JSONEncoder().encode(day).write(to: dayFile, options: .atomic)
    }

    private func loadActiveDays() -> Set<Int> {
        if let activeDays { return activeDays }
        let days = (try? Data(contentsOf: activeDaysFile)).flatMap { try? JSONDecoder().decode(Set<Int>.self, from: $0) } ?? []
        activeDays = days
        return days
    }

    // MARK: - Queue

    private func enqueue(_ report: TelemetryReport) {
        do {
            try queue.enqueue(report)
        } catch {
            Logger.app.errorFile("telemetry: could not queue a report: \(error)")
        }
    }

    func pending() -> [TelemetryReport] {
        queue.entries().map(\.report)
    }

    func lastSent() -> TelemetryReport? {
        queue.lastSent()
    }

    func deletePending() {
        queue.remove(queue.entries())
    }

    /// Sends the queue, ten reports per request, while `allowed` and the
    /// server takes them; backs off after a failure.
    func flush(allowed: Bool) async {
        guard allowed, level > .off, !sending else { return }
        sending = true
        defer { sending = false }
        while true {
            let batch = Array(queue.entries().prefix(Self.batchSize))
            guard !batch.isEmpty else { return }
            do {
                let accepted = try await sender.send(batch.map(\.report))
                queue.remove(batch)
                if accepted, let last = batch.last { queue.recordSent(last.report) }
                failures = 0
            } catch {
                failures += 1
                let delay = TelemetrySender.backoff(afterFailures: failures)
                Logger.app.infoFile("telemetry: sending failed (\(failures)); next try in \(Int(delay.components.seconds)) s")
                retry?.cancel()
                retry = Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    await self?.flush(allowed: allowed)
                }
                return
            }
        }
    }
}
