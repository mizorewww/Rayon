//
//  DiagnosticScrubber.swift
//  Telemetry
//
//  Turns MetricKit's diagnostic JSON into Diagnostic values by allow-list:
//  a key is read only when it maps to a number or an enum, so
//  composedMessage, arguments, virtualMemoryRegionInfo, binary names and
//  any key Apple adds later never reach a report.
//

import Foundation
import MachO

public struct DiagnosticScrubber: Sendable {
    /// Where a frame's binary comes from, by its name and UUID.
    public var origin: @Sendable (_ binaryName: String?, _ binaryUUID: UUID?) -> TelemetryReport.Frame.Origin

    /// The most frames one diagnostic keeps; deeper or wider trees are cut.
    static let frameLimit = 512

    public init(origin: @escaping @Sendable (String?, UUID?) -> TelemetryReport.Frame.Origin = { LoadedImages.current.origin(binaryName: $0, binaryUUID: $1) }) {
        self.origin = origin
    }

    /// The diagnostics in an `MXDiagnosticPayload.jsonRepresentation()`.
    public func diagnostics(fromPayload data: Data) -> [TelemetryReport.Diagnostic] {
        guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let kinds: [(String, TelemetryReport.Diagnostic.Kind)] = [
            ("crashDiagnostics", .crash),
            ("hangDiagnostics", .hang),
            ("cpuExceptionDiagnostics", .cpuException),
            ("diskWriteExceptionDiagnostics", .diskWriteException),
        ]
        return kinds.flatMap { key, kind in
            (payload[key] as? [[String: Any]] ?? []).map { diagnostic(from: $0, kind: kind) }
        }
    }

    func diagnostic(from json: [String: Any], kind: TelemetryReport.Diagnostic.Kind) -> TelemetryReport.Diagnostic {
        let meta = json["diagnosticMetaData"] as? [String: Any] ?? [:]
        let reason = (meta["objectiveCexceptionReason"] ?? meta["exceptionReason"]) as? [String: Any] ?? [:]
        var budget = Self.frameLimit
        let tree = json["callStackTree"] as? [String: Any] ?? [:]
        let stacks = (tree["callStacks"] as? [[String: Any]] ?? []).map { stack in
            TelemetryReport.CallStack(
                threadAttributed: stack["threadAttributed"] as? Bool ?? false,
                frames: frames(stack["callStackRootFrames"], budget: &budget)
            )
        }
        // A crash's other threads rarely help and cost the most; keep the one that crashed.
        let kept = kind == .crash && stacks.contains(where: \.threadAttributed) ? stacks.filter(\.threadAttributed) : stacks
        return TelemetryReport.Diagnostic(
            kind: kind,
            appVersion: (meta["appVersion"] as? String).flatMap { .init(parsing: $0, keepPatch: true) },
            osVersion: (meta["osVersion"] as? String).flatMap(Self.osVersion),
            exceptionType: Self.integer(meta["exceptionType"]),
            exceptionCode: Self.integer(meta["exceptionCode"]),
            signal: Self.integer(meta["signal"]),
            terminationReason: (meta["terminationReason"] as? String).map(Self.terminationReason),
            objcExceptionName: (reason["exceptionName"] as? String).flatMap { .init(rawValue: $0) },
            objcExceptionClass: (reason["className"] as? String).flatMap { .init(rawValue: $0) },
            hangDuration: (meta["hangDuration"] as? String).flatMap(Self.seconds).map { .init(seconds: $0) },
            callStacks: kept
        )
    }

    private func frames(_ value: Any?, budget: inout Int) -> [TelemetryReport.Frame] {
        var result: [TelemetryReport.Frame] = []
        for json in value as? [[String: Any]] ?? [] {
            guard budget > 0 else { break }
            budget -= 1
            let uuid = (json["binaryUUID"] as? String).flatMap(UUID.init(uuidString:))
            let origin = origin(json["binaryName"] as? String, uuid)
            let known = origin != .other
            result.append(TelemetryReport.Frame(
                origin: origin,
                binaryUUID: known ? uuid : nil,
                offset: known ? Self.integer(json["offsetIntoBinaryTextSegment"]) : nil,
                sampleCount: Self.integer(json["sampleCount"]) ?? 1,
                subFrames: frames(json["subFrames"], budget: &budget)
            ))
        }
        return result
    }

    static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue }
    }

    /// "macOS 15.4.1 (24E263)" or "iPhone OS 18.1 (22B83)" → 15.4, 18.1.
    static func osVersion(_ text: String) -> TelemetryReport.Version? {
        let token = text.split(separator: " ").first { $0.first?.isNumber == true }
        return token.flatMap { .init(parsing: String($0), keepPatch: false) }
    }

    /// "Namespace SIGNAL, Code 11 Segmentation fault: 11" → .signal.
    static func terminationReason(_ text: String) -> TelemetryReport.Diagnostic.TerminationReason {
        let words = text.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
        guard let index = words.firstIndex(of: "NAMESPACE"), index + 1 < words.count else { return .other }
        return switch words[index + 1] {
        case "SIGNAL": .signal
        case "CODESIGNING": .codeSigning
        case "WATCHDOG", "SPRINGBOARD": .watchdog
        case "JETSAM", "MEMORYSTATUS": .jetsam
        case "RUNNINGBOARD": .runningBoard
        case "FRONTBOARD": .frontBoard
        case "DYLD": .dyld
        case "LIBSYSTEM": .libsystem
        case "OBJC": .objc
        default: .other
        }
    }

    /// "20 sec", "1.5 sec", "250 ms", "2 min".
    static func seconds(_ text: String) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: "").split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        return switch parts[1].lowercased() {
        case "ms": value / 1000
        case "s", "sec", "secs", "second", "seconds": value
        case "min", "mins", "minute", "minutes": value * 60
        default: nil
        }
    }
}

/// The app's own executable and the system's loaded images, by UUID.
public struct LoadedImages: Sendable {
    public let appName: String?
    public let app: Set<UUID>
    public let system: Set<UUID>

    public static let current = LoadedImages()

    init() {
        var app = Set<UUID>()
        var system = Set<UUID>()
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        for index in 0 ..< _dyld_image_count() {
            guard let header = _dyld_get_image_header(index), let name = _dyld_get_image_name(index),
                  let uuid = Self.uuid(of: header)
            else { continue }
            let path = String(cString: name)
            if path == executable {
                app.insert(uuid)
            } else if path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/") {
                system.insert(uuid)
            }
        }
        appName = Bundle.main.executableURL?.lastPathComponent
        self.app = app
        self.system = system
    }

    public func origin(binaryName: String?, binaryUUID: UUID?) -> TelemetryReport.Frame.Origin {
        if let binaryUUID, app.contains(binaryUUID) { return .app }
        if let binaryUUID, system.contains(binaryUUID) { return .system }
        // A crash from an earlier build of the app has another UUID but the same name.
        if let binaryName, binaryName == appName { return .app }
        return .other
    }

    private static func uuid(of header: UnsafePointer<mach_header>) -> UUID? {
        guard header.pointee.magic == MH_MAGIC_64 else { return nil }
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0 ..< header.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if load.cmd == LC_UUID {
                return UUID(uuid: command.load(as: uuid_command.self).uuid)
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return nil
    }
}
