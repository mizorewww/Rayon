//
//  TelemetryEndpoint.swift
//  Telemetry
//

import Foundation

/// Where reports go: the Worker in Server/Telemetry on its own custom
/// domain, never workers.dev, which is unreliable from mainland China.
public enum TelemetryEndpoint {
    public static let url = URL(string: "https://telemetry.kfcv50.today/v1/reports")!
}
