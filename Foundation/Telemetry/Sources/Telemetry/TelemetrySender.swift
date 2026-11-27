//
//  TelemetrySender.swift
//  Telemetry
//

import Foundation

/// Posts reports to the endpoint on an ephemeral session: no cookies, no
/// cache, nothing kept between requests.
public struct TelemetrySender: Sendable {
    public let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = TelemetryEndpoint.url) {
        self.init(endpoint: endpoint, configuration: .ephemeral)
    }

    init(endpoint: URL, configuration: URLSessionConfiguration) {
        self.endpoint = endpoint
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    struct Batch: Encodable {
        let reports: [TelemetryReport]
    }

    /// True when the server took the reports, false when it refused them for
    /// good (they would never be accepted, so they are dropped); throws when
    /// they should be tried again later.
    public func send(_ reports: [TelemetryReport]) async throws -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The system's agent names the exact OS build; the server ignores it anyway.
        request.setValue("Rayon", forHTTPHeaderField: "User-Agent")
        request.httpBody = try TelemetryQueue.encoder().encode(Batch(reports: reports))
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200 ..< 300: return true
        case 400, 413, 422: return false
        default: throw URLError(.badServerResponse)
        }
    }

    /// One minute after the first failure, doubling up to six hours.
    static func backoff(afterFailures failures: Int) -> Duration {
        .seconds(min(60 * (1 << min(max(failures - 1, 0), 12)), 6 * 3600))
    }
}
