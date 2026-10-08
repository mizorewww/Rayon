//
//  ProcParsers.swift
//  MachineStatus
//
//  Pure parsers for Linux /proc and os-release payloads, extracted from
//  the ServerStatus remote initializers so they can be unit tested
//  offline with fixtures.
//

import Foundation

enum ProcParsers {
    // MARK: - /proc/meminfo

    /// Parses `/proc/meminfo` content into a keyed dictionary (values in kB).
    static func parseMeminfo(_ raw: String) -> [String: Float] {
        var info = [String: Float]()
        for line in raw.components(separatedBy: "\n") where line.count > 0 {
            var line = line
            while line.contains("  ") {
                line = line.replacingOccurrences(of: "  ", with: " ")
            }
            line = line.replacingOccurrences(of: ":", with: "")
            let cut = line.components(separatedBy: " ")
            guard cut.count == 3, cut[2].uppercased() == "KB" else {
                continue
            }
            info[cut[0].uppercased()] = Float(cut[1])
        }
        return info
    }

    // MARK: - /proc/stat

    /// Parses one `/proc/stat` sample into the aggregate "cpu" row and
    /// per-core rows.
    static func parseProcStat(_ raw: String)
        -> (summary: ServerStatus.ProcessInfoElement?, cores: [String: ServerStatus.ProcessInfoElement])
    {
        var result = [String: ServerStatus.ProcessInfoElement]()
        var summary: ServerStatus.ProcessInfoElement?
        for line in raw.components(separatedBy: "\n") {
            var line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("cpu") else {
                continue
            }
            while line.contains("  ") {
                line = line.replacingOccurrences(of: "  ", with: " ")
            }
            let lineElement = line.components(separatedBy: " ")
            guard lineElement.count == 11 else {
                continue
            }
            let key = lineElement[0]
            let element = ServerStatus.ProcessInfoElement(
                user: Float(lineElement[1]) ?? 0,
                nice: Float(lineElement[2]) ?? 0,
                system: Float(lineElement[3]) ?? 0,
                idle: Float(lineElement[4]) ?? 0,
                iowait: Float(lineElement[5]) ?? 0,
                irq: Float(lineElement[6]) ?? 0,
                softIrq: Float(lineElement[7]) ?? 0,
                steal: Float(lineElement[8]) ?? 0,
                guest: Float(lineElement[9]) ?? 0
            )
            if key == "cpu" {
                summary = element
            } else {
                result[key] = element
            }
        }
        return (summary, result)
    }

    /// Computes usage percentages between two /proc/stat samples.
    /// Returns zeros when counters did not advance (idle machine), rather
    /// than dividing by zero and feeding NaN into the UI.
    static func calculatePercent(
        priv: ServerStatus.ProcessInfoElement,
        curr: ServerStatus.ProcessInfoElement
    ) -> ServerStatus.ProcessPercentInfo {
        let preAll = priv.user + priv.nice + priv.system + priv.idle + priv.iowait + priv.irq + priv.softIrq + priv.steal + priv.guest
        let nowAll = curr.user + curr.nice + curr.system + curr.idle + curr.iowait + curr.irq + curr.softIrq + curr.steal + curr.guest

        let total = nowAll - preAll
        guard total > 0 else {
            return ServerStatus.ProcessPercentInfo()
        }
        let privUsedTotal = priv.user + priv.nice + priv.system + priv.iowait
        let currUsedTotal = curr.user + curr.nice + curr.system + curr.iowait

        return ServerStatus.ProcessPercentInfo(
            system: (curr.system - priv.system) / total * 100,
            user: (curr.user - priv.user) / total * 100,
            iowait: (curr.iowait - priv.iowait) / total * 100,
            nice: (curr.nice - priv.nice) / total * 100,
            sum: (currUsedTotal - privUsedTotal) / total * 100
        )
    }

    // MARK: - /etc/os-release

    static func stripSurroundingQuotes(_ str: String) -> String {
        guard str.count > 2 else { return str }
        let doubleQuoted = str.hasPrefix("\"") && str.hasSuffix("\"")
        let singleQuoted = str.hasPrefix("'") && str.hasSuffix("'")
        guard doubleQuoted || singleQuoted else { return str }
        return String(str.dropFirst().dropLast())
    }

    /// Extracts a display name from /etc/os-release content, preferring
    /// PRETTY_NAME over NAME, unquoting the value.
    static func parseOsReleaseName(_ intake: String) -> String {
        var pretty: String?
        var name: String?
        for item in intake.components(separatedBy: "\n") {
            if item.hasPrefix("PRETTY_NAME=") {
                pretty = String(item.dropFirst("PRETTY_NAME=".count))
                break
            }
            if item.hasPrefix("NAME=") {
                name = String(item.dropFirst("NAME=".count))
            }
        }
        if let pretty {
            return stripSurroundingQuotes(pretty)
        }
        if let name {
            return stripSurroundingQuotes(name)
        }
        return "Generic Linux"
    }

    // MARK: - /proc/loadavg

    /// Parses `/proc/loadavg` ("0.27 0.34 0.39 2/916 23817") into
    /// load averages and process counters.
    static func parseLoadavg(_ intake: String) -> ServerStatus.SystemLoadInternal {
        var ret = ServerStatus.SystemLoadInternal()
        var get = intake
        while get.contains("  ") {
            get = get.replacingOccurrences(of: "  ", with: " ")
        }
        let cut = get.components(separatedBy: " ")
        guard cut.count == 5 else { return .init() }
        if let l1 = Float(cut[0]), l1 != .infinity { ret.load1avg = l1 } else { return .init() }
        if let l5 = Float(cut[1]), l5 != .infinity { ret.load5avg = l5 } else { return .init() }
        if let l15 = Float(cut[2]), l15 != .infinity { ret.load15avg = l15 } else { return .init() }
        let process = cut[3].components(separatedBy: "/")
        if process.count == 2,
           let running = Int(process[0]),
           let total = Int(process[1])
        {
            ret.runningProcess = running
            ret.totalProcess = total
        } else {
            return .init()
        }
        return ret
    }
}
