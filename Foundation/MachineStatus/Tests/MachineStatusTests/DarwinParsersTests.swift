//
//  DarwinParsersTests.swift
//  MachineStatusTests
//

@testable import MachineStatus
import XCTest

final class DarwinParsersTests: XCTestCase {
    func testProcessTimesParseEveryPsTimeFormat() {
        let listing = """
            1 Ss    20:20.13  79:18.20
          345 R    1:03:47.84 2-01:55:54.50
          348 S       0:54.69   1:57.69
          bad line
        """
        let parsed = ProcParsers.parseDarwinProcessTimes(listing)
        XCTAssertEqual(parsed.times.count, 3)
        XCTAssertEqual(parsed.running, 1)
        XCTAssertEqual(parsed.times[1]?.total ?? 0, 4758.2, accuracy: 0.001)
        XCTAssertEqual(parsed.times[345]?.user ?? 0, 3827.84, accuracy: 0.001)
        // 2 days, 1 hour, 55 minutes, 54.5 seconds.
        XCTAssertEqual(parsed.times[345]?.total ?? 0, 179_754.5, accuracy: 0.001)
    }

    func testDarwinCPUIsTheProcessTimeDifferenceOverCapacity() {
        let before: [Int: ProcParsers.DarwinCPUTime] = [
            1: .init(user: 10, total: 20),
            2: .init(user: 5, total: 5),
            3: .init(user: 100, total: 100), // exits before the next round
        ]
        let after: [Int: ProcParsers.DarwinCPUTime] = [
            1: .init(user: 12, total: 23), // 2s user, 1s system
            2: .init(user: 6, total: 6), // 1s user
            4: .init(user: 1, total: 2), // new: counts whole
        ]
        // 2 CPUs over 3 seconds: 6 CPU-seconds of capacity, 6 used.
        let percent = ProcParsers.darwinCPUPercent(before: before, after: after, interval: 3, cpuCount: 2)
        XCTAssertEqual(percent.sumUsed, 100, accuracy: 0.001)
        XCTAssertEqual(percent.sumUser, 66.667, accuracy: 0.001)
        XCTAssertEqual(percent.sumSystem, 33.333, accuracy: 0.001)
        XCTAssertEqual(ProcParsers.darwinCPUPercent(before: after, after: after, interval: 3, cpuCount: 2).sumUsed, 0)
    }

    func testDarwinLoadavg() {
        let load = ProcParsers.parseDarwinLoadavg("{ 10.83 6.62 6.06 }\n")
        XCTAssertEqual(load?.load1 ?? 0, 10.83, accuracy: 0.001)
        XCTAssertEqual(load?.load15 ?? 0, 6.06, accuracy: 0.001)
        XCTAssertNil(ProcParsers.parseDarwinLoadavg("garbage"))
    }

    func testDarwinMemoryUsesPageSizeAndSwapUnits() {
        let fixture = """
        hw.memsize: 17179869184
        hw.pagesize: 16384
        vm.swapusage: total = 2048.00M  used = 512.00M  free = 1536.00M  (encrypted)
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                                     4497.
        Pages speculative:                              1547.
        Pages occupied by compressor:                  21904.
        File-backed pages:                            407513.
        Anonymous pages:                              486560.
        """
        let memory = ServerStatus.MemoryInfo(darwinMemory: fixture)
        XCTAssertEqual(memory.memTotal, 16_777_216)
        XCTAssertEqual(memory.memFree, 96704)
        XCTAssertEqual(memory.memCached, 6_495_456)
        XCTAssertEqual(memory.memBuffers, 0)
        XCTAssertEqual(memory.swapTotal, 2_097_152)
        XCTAssertEqual(memory.swapFree, 1_572_864)
        XCTAssertEqual(memory.swapUsed, 0.25, accuracy: 0.001)
        XCTAssertGreaterThan(memory.phyUsed, 0)
        XCTAssertLessThan(memory.phyUsed, 1)
    }

    func testDarwinMemoryFallsBackToVMStatPageSize() {
        let fixture = """
        hw.memsize: 8589934592
        Mach Virtual Memory Statistics: (page size of 4096 bytes)
        Pages free: 1000.
        Pages speculative: 500.
        File-backed pages: 2000.
        """
        let memory = ServerStatus.MemoryInfo(darwinMemory: fixture)
        XCTAssertEqual(memory.memFree, 6000)
        XCTAssertEqual(memory.memCached, 6000)
    }

    func testDarwinNetstatReadsLinkRowsAndOptionalAddressColumn() {
        let before = """
        Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0        16384 <Link#1>                          10     0       100       10     0       100     0
        en0        1500  <Link#11>   be:c4:9b:88:a5:08    20     0      1000       30     0      2000     0
        gif0*      1280  <Link#2>                             0     0         0        0     0         0     0
        en0        1500  192.168.31    192.168.31.241      20     -      1000       30     -      2000     -
        """
        let after = """
        lo0        16384 <Link#1>                          15     0       150       20     0       250     0
        en0        1500  <Link#11>   be:c4:9b:88:a5:08    25     0      3000       40     0      6000     0
        gif0       1280  <Link#2>                             1     0        64        2     0       128     0
        """
        let network = ServerStatus.NetworkInfo(
            before: ProcParsers.parseDarwinNetstat(before),
            after: ProcParsers.parseDarwinNetstat(after),
            interval: 1
        )
        XCTAssertEqual(network.elements.count, 3)
        XCTAssertEqual(network.elements.first { $0.device == "en0" }?.rxBytesPerSec, 2000)
        XCTAssertEqual(network.elements.first { $0.device == "en0" }?.txBytesPerSec, 4000)
        XCTAssertEqual(network.elements.first { $0.device == "lo0" }?.rxBytesPerSec, 50)
        XCTAssertEqual(network.elements.first { $0.device == "gif0" }?.txBytesPerSec, 128)
    }

    func testDarwinUptimeAndReleaseName() {
        let uptime = "1000\n{ sec = 750, usec = 912078 } Sat Oct 17 21:39:26 2026\n"
        XCTAssertEqual(ProcParsers.parseDarwinUptime(uptime), 250)
        XCTAssertEqual(ProcParsers.parseDarwinUptime("garbage"), 0)

        let release = """
        ProductName:            macOS
        ProductVersion:         27.2
        BuildVersion:           26B5112a
        """
        XCTAssertEqual(ProcParsers.parseDarwinReleaseName(release), "macOS 27.2")
    }

    func testMonitorScriptContainsDarwinProbesAndLinuxFallbacks() {
        let script = ServerStatus.monitorScript(includeStatic: true)
        XCTAssertTrue(script.contains("/bin/ps -A -o pid=,state=,utime=,time="))
        XCTAssertTrue(script.contains("vm.loadavg"))
        XCTAssertTrue(script.contains("hw.logicalcpu"))
        XCTAssertTrue(script.contains("/usr/sbin/netstat -ibn"))
        XCTAssertTrue(script.contains("/usr/bin/vm_stat"))
        XCTAssertTrue(script.contains("vm.swapusage"))
        XCTAssertTrue(script.contains("/usr/bin/sw_vers"))
        XCTAssertTrue(script.contains("kern.boottime"))
        XCTAssertTrue(script.contains("/bin/cat /proc/meminfo"))
    }
}
