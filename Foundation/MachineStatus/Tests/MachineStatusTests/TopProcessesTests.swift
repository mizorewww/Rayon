//
//  TopProcessesTests.swift
//  MachineStatusTests
//

@testable import MachineStatus
import XCTest

final class TopProcessesTests: XCTestCase {
    /// `ps -eo pid,user,pcpu,pmem,rss,comm --sort=-pcpu | head -13` (procps-ng).
    private let procpsByCPU = """
        PID USER     %CPU %MEM   RSS COMMAND
       2214 postgres 38.2  6.1 1002400 postgres
       1873 www-data 12.6  0.4 64200 nginx
      40211 deploy    9.8  3.2 524800 node
      40388 deploy    4.0  0.0  3412 ps
        912 root      2.1  0.9 148000 dockerd
         77 root      0.3  0.0     0 kworker/1:1-events
          1 root      0.1  0.1 12900 systemd
    """

    /// `ps -eo pid,user,pcpu,pmem,rss,comm --sort=-rss | head -13`.
    private let procpsByMemory = """
        PID USER     %CPU %MEM   RSS COMMAND
       2214 postgres 38.2  6.1 1002400 postgres
      40211 deploy    9.8  3.2 524800 node
        912 root      2.1  0.9 148000 dockerd
    """

    /// Plain busybox `ps` (BusyBox v1.36, the default columns).
    private let busyboxPlain = """
    PID   USER     TIME  COMMAND
        1 root      0:02 /sbin/init
        2 root      0:00 [kthreadd]
      812 root      0:10 /usr/sbin/dropbear -F -P /var/run/dropbear.pid
      901 nobody    1:42 dnsmasq -C /var/etc/dnsmasq.conf
     4118 root      0:00 /bin/sh -c RAYON_KERNEL="$(/usr/bin/uname -s 2>/dev/null || uname -s)"; echo
     4120 root      0:00 ps
     4121 root      0:00 head -500
    """

    /// busybox built with the VSZ and STAT columns, large sizes shortened.
    private let busyboxWithSizes = """
      PID USER       VSZ STAT COMMAND
        1 root      1680 S    /sbin/init
      812 root     12.4m S    /usr/sbin/dropbear -F
      901 nobody    3020 S    dnsmasq
    """

    /// `ps -Ao pid,user,pcpu,pmem,rss,comm -r | head -13` on macOS.
    private let darwinByCPU = """
      PID USER              %CPU %MEM    RSS COMM
      418 _windowserver     79.0  0.9 1272560 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
    97078 alice             46.8  0.2 285616 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend
     6120 alice             12.5  2.1 701232 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
    98001 alice              0.0  0.0   1200 /bin/ps
        1 root               0.0  0.1  31024 /sbin/launchd
    """

    func testProcpsListReadsEveryColumnInOrder() {
        let processes = ProcParsers.parseProcessList(procpsByCPU, order: .cpu)
        XCTAssertEqual(processes.map(\.command), ["postgres", "nginx", "node", "dockerd", "kworker/1:1-events", "systemd"])
        XCTAssertEqual(processes.first, .init(pid: 2214, user: "postgres", command: "postgres", cpuPercent: 38.2, memoryPercent: 6.1, residentKB: 1_002_400))
        XCTAssertEqual(processes[4].residentKB, 0)
    }

    func testTheProbeItselfIsDropped() {
        XCTAssertFalse(ProcParsers.parseProcessList(procpsByCPU, order: .cpu).contains { $0.command == "ps" })
        XCTAssertEqual(ProcParsers.parseProcessList(busyboxPlain, order: .cpu).map(\.pid), [1, 2, 812, 901])
        XCTAssertFalse(ProcParsers.parseProcessList(darwinByCPU, order: .cpu).contains { $0.command == "ps" })
    }

    func testTheListStopsAtTheLimit() {
        XCTAssertEqual(ProcParsers.parseProcessList(procpsByCPU, order: .cpu, limit: 2).map(\.pid), [2214, 1873])
    }

    func testMemoryOrderUsesResidentSize() {
        let processes = ProcParsers.parseProcessList(procpsByCPU, order: .memory)
        XCTAssertEqual(processes.prefix(3).map(\.command), ["postgres", "node", "dockerd"])
    }

    func testBusyboxPlainListingKeepsPsOrderAndShortensPaths() {
        let processes = ProcParsers.parseProcessList(busyboxPlain, order: .cpu)
        XCTAssertEqual(processes.map(\.command), ["init", "[kthreadd]", "dropbear -F -P /var/run/dropbear.pid", "dnsmasq -C /var/etc/dnsmasq.conf"])
        XCTAssertEqual(processes[3].user, "nobody")
        XCTAssertNil(processes[0].cpuPercent)
        XCTAssertNil(processes[0].memoryPercent)
        XCTAssertNil(processes[0].residentKB)
    }

    func testBusyboxSizesAreNotMistakenForResidentMemory() {
        // VSZ is address space, not memory in use: it stays unread.
        let processes = ProcParsers.parseProcessList(busyboxWithSizes, order: .memory)
        XCTAssertEqual(processes.map(\.pid), [1, 812, 901])
        XCTAssertEqual(processes[1].command, "dropbear -F")
        XCTAssertNil(processes[1].residentKB)
    }

    func testBusyboxShortenedSizesParse() {
        XCTAssertEqual(ProcParsers.parseKilobytes("12.4m"), 12.4 * 1024)
        XCTAssertEqual(ProcParsers.parseKilobytes("2g"), 2 * 1024 * 1024)
        XCTAssertEqual(ProcParsers.parseKilobytes("1680"), 1680)
        XCTAssertNil(ProcParsers.parseKilobytes("-"))
    }

    func testDarwinListShortensExecutablePathsWithSpaces() {
        let processes = ProcParsers.parseProcessList(darwinByCPU, order: .cpu)
        XCTAssertEqual(processes.map(\.command), ["WindowServer", "swift-frontend", "Google Chrome", "launchd"])
        XCTAssertEqual(processes[0].user, "_windowserver")
        XCTAssertEqual(processes[0].cpuPercent, 79.0)
        XCTAssertEqual(processes[2].residentKB, 701_232)
    }

    func testGarbageAndMissingHeadersGiveNothing() {
        XCTAssertTrue(ProcParsers.parseProcessList("", order: .cpu).isEmpty)
        XCTAssertTrue(ProcParsers.parseProcessList("ps: unrecognized option '--sort=-pcpu'\n", order: .cpu).isEmpty)
        XCTAssertTrue(ProcParsers.parseProcessList("  1 root 0.0 init\n", order: .cpu).isEmpty)
    }

    func testBothListsComeFromTheirOwnSections() {
        let info = ServerStatus.TopProcessesInfo(cpuSection: procpsByCPU, memorySection: procpsByMemory)
        XCTAssertEqual(info.byCPU.first?.command, "postgres")
        XCTAssertEqual(info.byMemory.map(\.command), ["postgres", "node", "dockerd"])
    }

    func testBusyboxFillsBothListsFromItsOneListing() {
        let info = ServerStatus.TopProcessesInfo(cpuSection: busyboxPlain, memorySection: "")
        XCTAssertEqual(info.byCPU.count, 4)
        XCTAssertEqual(info.byMemory.map(\.pid), info.byCPU.map(\.pid))
    }

    func testMonitorScriptAsksForBothLists() {
        let script = ServerStatus.monitorScript(includeStatic: false)
        XCTAssertTrue(script.contains("echo '\(ServerStatus.sectionMarkerPrefix)procs-cpu\(ServerStatus.sectionMarkerSuffix)'"))
        XCTAssertTrue(script.contains("echo '\(ServerStatus.sectionMarkerPrefix)procs-mem\(ServerStatus.sectionMarkerSuffix)'"))
        XCTAssertTrue(script.contains("--sort=-pcpu"))
        XCTAssertTrue(script.contains("--sort=-rss"))
        XCTAssertTrue(script.contains("/bin/ps -Ao pid,user,pcpu,pmem,rss,comm -r"))
        XCTAssertTrue(script.contains("/bin/ps -Ao pid,user,pcpu,pmem,rss,comm -m"))
    }
}
