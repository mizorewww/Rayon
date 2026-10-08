//
//  ProcParsersTests.swift
//  MachineStatusTests
//
//  Fixture-driven tests for the Linux /proc and os-release parsers.
//

@testable import MachineStatus
import XCTest

final class ProcParsersTests: XCTestCase {
    // MARK: - /proc/meminfo

    private let meminfoFixture = """
    MemTotal:       16384000 kB
    MemFree:         1024000 kB
    MemAvailable:    8192000 kB
    Buffers:          512000 kB
    Cached:          4096000 kB
    SwapCached:            0 kB
    SwapTotal:       2097152 kB
    SwapFree:        1048576 kB
    Hugepagesize:       2048 kB
    """

    func testMeminfoParsesKeyedValues() {
        let info = ProcParsers.parseMeminfo(meminfoFixture)
        XCTAssertEqual(info["MEMTOTAL"], 16_384_000)
        XCTAssertEqual(info["MEMFREE"], 1_024_000)
        XCTAssertEqual(info["BUFFERS"], 512_000)
        XCTAssertEqual(info["CACHED"], 4_096_000)
        XCTAssertEqual(info["SWAPTOTAL"], 2_097_152)
        XCTAssertEqual(info["SWAPFREE"], 1_048_576)
        // Lines without a kB suffix are ignored.
        XCTAssertNil(info["HUGE_PAGESIZE:"])
    }

    func testSwapUsageIsRelativeToSwapTotal() {
        // Regression: swap usage was divided by physical memory total,
        // making the reported swap percentage always wrong.
        let info = ServerStatus.MemoryInfo(
            total: 16_384_000, free: 1_024_000, buffers: 512_000, cached: 4_096_000,
            swapTotal: 2_097_152, swapFree: 1_048_576
        )
        XCTAssertEqual(info.swapUsed, 0.5, accuracy: 0.001)
        XCTAssertEqual(info.phyUsed, (16_384_000 - 1_024_000 - 4_096_000 - 512_000) / 16_384_000, accuracy: 0.001)
    }

    func testZeroSwapDoesNotDivideByZero() {
        let info = ServerStatus.MemoryInfo(
            total: 16_384_000, free: 1_024_000, buffers: 0, cached: 0,
            swapTotal: 0, swapFree: 0
        )
        XCTAssertEqual(info.swapUsed, 0)
        XCTAssertFalse(info.swapUsed.isNaN)
    }

    // MARK: - /proc/stat

    private let procStatFixture = """
    cpu  100 0 200 1600 50 0 10 0 0 0
    cpu0 50 0 100 800 25 0 5 0 0 0
    cpu1 50 0 100 800 25 0 5 0 0 0
    intr 123456
    """

    func testProcStatParsesSummaryAndCores() {
        let (summary, cores) = ProcParsers.parseProcStat(procStatFixture)
        XCTAssertEqual(summary?.user, 100)
        XCTAssertEqual(summary?.idle, 1600)
        XCTAssertEqual(cores["cpu0"]?.system, 100)
        XCTAssertEqual(cores["cpu1"]?.iowait, 25)
        XCTAssertEqual(cores.count, 2)
    }

    func testPercentageBetweenSamples() {
        let (privSum, _) = ProcParsers.parseProcStat(procStatFixture)
        let currRaw = procStatFixture
            .replacingOccurrences(of: "cpu  100", with: "cpu  200") // user +100
        let (currSum, _) = ProcParsers.parseProcStat(currRaw)
        guard let priv = privSum, let curr = currSum else {
            XCTFail("missing summary rows")
            return
        }
        let percent = ProcParsers.calculatePercent(priv: priv, curr: curr)
        // total delta is 100, all of it user time
        XCTAssertEqual(percent.sumUser, 100, accuracy: 0.01)
        XCTAssertEqual(percent.sumUsed, 100, accuracy: 0.01)
    }

    func testIdenticalSamplesYieldZeroNotNaN() {
        // Regression: an idle machine can report identical counters twice;
        // dividing by the zero delta produced NaN/inf percentages.
        let (sum, _) = ProcParsers.parseProcStat(procStatFixture)
        guard let sum else {
            XCTFail("missing summary row")
            return
        }
        let percent = ProcParsers.calculatePercent(priv: sum, curr: sum)
        XCTAssertEqual(percent.sumUsed, 0)
        XCTAssertFalse(percent.sumUsed.isNaN)
        XCTAssertFalse(percent.sumSystem.isInfinite)
    }

    // MARK: - /etc/os-release

    func testOsReleasePrefersPrettyNameAndStripsDoubleQuotes() {
        let fixture = """
        NAME="Ubuntu"
        VERSION_ID="22.04"
        PRETTY_NAME="Ubuntu 22.04.1 LTS"
        """
        XCTAssertEqual(ProcParsers.parseOsReleaseName(fixture), "Ubuntu 22.04.1 LTS")
    }

    func testOsReleaseFallsBackToName() {
        XCTAssertEqual(ProcParsers.parseOsReleaseName("NAME=\"Debian GNU/Linux\""), "Debian GNU/Linux")
    }

    func testOsReleaseStripsSingleQuotes() {
        // Regression: the old condition compared prefixes against double
        // quotes but suffixes against single quotes, so nothing was stripped.
        XCTAssertEqual(ProcParsers.parseOsReleaseName("NAME='Fedora Linux'"), "Fedora Linux")
    }

    func testOsReleaseUnquotedAndMissing() {
        XCTAssertEqual(ProcParsers.parseOsReleaseName("NAME=Alpine Linux"), "Alpine Linux")
        XCTAssertEqual(ProcParsers.parseOsReleaseName(""), "Generic Linux")
    }

    // MARK: - /proc/loadavg

    func testLoadavgParses() {
        let load = ProcParsers.parseLoadavg("0.27 0.34 0.39 2/916 23817")
        XCTAssertEqual(load.load1avg, 0.27, accuracy: 0.001)
        XCTAssertEqual(load.load5avg, 0.34, accuracy: 0.001)
        XCTAssertEqual(load.load15avg, 0.39, accuracy: 0.001)
        XCTAssertEqual(load.runningProcess, 2)
        XCTAssertEqual(load.totalProcess, 916)
    }

    func testLoadavgMalformedReturnsZero() {
        let load = ProcParsers.parseLoadavg("garbage")
        XCTAssertEqual(load.load1avg, 0)
        XCTAssertEqual(load.totalProcess, 0)
    }
}
