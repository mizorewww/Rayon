//
//  TelemetryEndpoint.swift
//  Telemetry
//

import Foundation

/// Where reports go: the Worker in Server/Telemetry, on its own domain,
/// never workers.dev. While the host is the placeholder nothing is sent;
/// reports wait in the queue.
public enum TelemetryEndpoint {
    static let placeholderHost = "telemetry.example.invalid"

    public static let url = URL(string: "https://\(placeholderHost)/v1/reports")!

    public static var isConfigured: Bool {
        url.host() != placeholderHost
    }
}
