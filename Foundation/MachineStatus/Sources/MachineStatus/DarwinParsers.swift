//
//  DarwinParsers.swift
//  MachineStatus
//

import Foundation

extension ProcParsers {
    /// A process's accumulated CPU time in seconds.
    struct DarwinCPUTime: Equatable, Sendable {
        let user: Double
        let total: Double
    }

    /// Reads `ps -A -o pid=,state=,utime=,time=`: per pid the accumulated
    /// user and user+system time, plus the running and total process
    /// counts top used to report.
    static func parseDarwinProcessTimes(_ raw: String) -> (times: [Int: DarwinCPUTime], running: Int) {
        var times = [Int: DarwinCPUTime]()
        var running = 0
        for line in raw.components(separatedBy: "\n") {
            let fields = splitWhitespaceRuns(line)
            guard fields.count == 4,
                  let pid = Int(fields[0]),
                  let user = parseCPUTime(fields[2]),
                  let total = parseCPUTime(fields[3])
            else {
                continue
            }
            times[pid] = DarwinCPUTime(user: user, total: total)
            if fields[1].hasPrefix("R") { running += 1 }
        }
        return (times, running)
    }

    /// Parses ps's `[[dd-]hh:]mm:ss.cc` CPU time into seconds.
    static func parseCPUTime(_ token: Substring) -> Double? {
        var rest = token
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let value = Double(rest[..<dash]) else { return nil }
            days = value
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":")
        guard (2 ... 3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return days * 86400 + seconds
    }

    /// CPU usage between two process-time readings `interval` seconds
    /// apart, over `cpuCount` logical CPUs. A pid new since the last
    /// reading counts whole (it started inside the interval); a pid whose
    /// time went back was reused and counts the same way.
    static func darwinCPUPercent(
        before: [Int: DarwinCPUTime],
        after: [Int: DarwinCPUTime],
        interval: Double,
        cpuCount: Int
    ) -> ServerStatus.ProcessPercentInfo {
        let capacity = interval * Double(cpuCount)
        guard capacity > 0 else { return .init() }
        var user = 0.0
        var total = 0.0
        for (pid, now) in after {
            if let then = before[pid], now.total >= then.total {
                user += max(0, now.user - then.user)
                total += now.total - then.total
            } else {
                user += now.user
                total += now.total
            }
        }
        let used = min(100, total / capacity * 100)
        let userShare = min(used, user / capacity * 100)
        return .init(system: Float(used - userShare), user: Float(userShare), iowait: 0, nice: 0, sum: Float(used))
    }

    /// Reads `sysctl -n vm.loadavg` ("{ 1.23 2.34 3.45 }").
    static func parseDarwinLoadavg(_ raw: String) -> (load1: Float, load5: Float, load15: Float)? {
        let values = splitWhitespaceRuns(raw).compactMap { Float($0) }
        guard values.count == 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    static func parseDarwinUptime(_ raw: String) -> Double {
        let fields = splitWhitespaceRuns(raw)
        guard let now = fields.first.flatMap({ Double($0) }),
              let secIndex = fields.firstIndex(of: "sec"),
              secIndex + 2 < fields.count,
              fields[secIndex + 1] == "=",
              let boot = Double(fields[secIndex + 2].trimmingCharacters(in: CharacterSet(charactersIn: ",")))
        else {
            return 0
        }
        return max(0, now - boot)
    }

    static func parseDarwinReleaseName(_ raw: String) -> String {
        var productName: String?
        var productVersion: String?
        for line in raw.components(separatedBy: "\n") {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2 else { continue }
            let key = fields[0].trimmingCharacters(in: .whitespaces)
            let value = fields[1].trimmingCharacters(in: .whitespaces)
            if key == "ProductName" {
                productName = value
            }
            if key == "ProductVersion" {
                productVersion = value
            }
        }
        if let productName, let productVersion {
            return "\(productName) \(productVersion)"
        }
        return productName ?? "macOS"
    }

    private static func parseDarwinKilobytes(_ token: Substring) -> Double {
        let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unit = text.last else { return 0 }
        let scales = ["K": 1.0, "M": 1024.0, "G": 1_048_576.0, "T": 1_073_741_824.0]
        if let scale = scales[String(unit).uppercased()], let value = Double(text.dropLast()) {
            return value * scale
        }
        return Double(text) ?? 0
    }

    static func parseDarwinMemory(_ raw: String) -> (
        total: Double, free: Double, cached: Double, swapTotal: Double, swapFree: Double
    ) {
        var total = 0.0
        var pageSize = 0.0
        var pages = [String: Double]()
        var swapTotal = 0.0
        var swapFree = 0.0

        for line in raw.components(separatedBy: "\n") {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2 else { continue }
            let key = fields[0].trimmingCharacters(in: .whitespaces)
            let value = fields[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "hw.memsize":
                total = (Double(value) ?? 0) / 1024
            case "hw.pagesize":
                pageSize = Double(value) ?? 0
            case "vm.swapusage":
                let swapFields = splitWhitespaceRuns(value)
                if let index = swapFields.firstIndex(of: "total"), index + 2 < swapFields.count {
                    swapTotal = parseDarwinKilobytes(swapFields[index + 2])
                }
                if let index = swapFields.firstIndex(of: "free"), index + 2 < swapFields.count {
                    swapFree = parseDarwinKilobytes(swapFields[index + 2])
                }
            case "Pages free", "Pages speculative", "File-backed pages":
                pages[key] = Double(value.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            default:
                continue
            }
        }

        if pageSize == 0,
           let header = raw.components(separatedBy: "\n").first(where: { $0.contains("page size of") })
        {
            let fields = splitWhitespaceRuns(header)
            if let index = fields.firstIndex(of: "of"), index + 1 < fields.count {
                pageSize = Double(fields[index + 1]) ?? 0
            }
        }
        let freePages = (pages["Pages free"] ?? 0) + (pages["Pages speculative"] ?? 0)
        let cachedPages = max(0, (pages["File-backed pages"] ?? 0) - (pages["Pages speculative"] ?? 0))
        let kilobytesPerPage = pageSize / 1024
        return (
            total: total,
            free: freePages * kilobytesPerPage,
            cached: cachedPages * kilobytesPerPage,
            swapTotal: swapTotal,
            swapFree: swapFree
        )
    }

    static func parseDarwinNetstat(_ raw: String) -> [String: (rx: Int, tx: Int)] {
        var result = [String: (rx: Int, tx: Int)]()
        for line in raw.components(separatedBy: "\n") {
            let fields = splitWhitespaceRuns(line)
            guard fields.count >= 10,
                  fields[2].hasPrefix("<Link#"),
                  let rx = Int(fields[fields.count - 5]),
                  let tx = Int(fields[fields.count - 2])
            else {
                continue
            }
            var device = String(fields[0])
            if device.hasSuffix("*") {
                device.removeLast()
            }
            result[device] = (rx, tx)
        }
        return result
    }
}
