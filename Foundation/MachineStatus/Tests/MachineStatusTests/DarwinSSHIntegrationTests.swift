//
//  DarwinSSHIntegrationTests.swift
//  MachineStatusTests
//

#if os(macOS)
    @testable import MachineStatus
    import XCTest

    final class DarwinSSHIntegrationTests: XCTestCase {
        func testGeneratedMonitorScriptOnDarwinHost() throws {
            let environment = ProcessInfo.processInfo.environment
            guard let host = environment["RAYON_SSH_TEST_HOST"], !host.isEmpty else {
                throw XCTSkip("Set RAYON_SSH_TEST_HOST to run the SSH integration test")
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                host,
                "/bin/sh", "-s",
            ]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            try process.run()
            let script = ServerStatus.monitorScript(includeStatic: true)
            input.fileHandleForWriting.write(Data(script.utf8))
            input.fileHandleForWriting.closeFile()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                XCTFail("ssh failed: \(String(decoding: errorData, as: UTF8.self))")
                return
            }

            let sections = ProcParsers.splitMonitorSections(String(decoding: outputData, as: UTF8.self))
            XCTAssertEqual(sections["platform"]?.trimmingCharacters(in: .whitespacesAndNewlines), "Darwin")
            XCTAssertEqual(sections["hostname"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, false)
            XCTAssertTrue(ProcParsers.parseDarwinReleaseName(sections["os-release"] ?? "").contains("macOS"))

            let processes = ProcParsers.parseDarwinProcessTimes(sections["cpu"] ?? "")
            XCTAssertGreaterThan(processes.times.count, 0)
            XCTAssertGreaterThan(Int((sections["ncpu"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0, 0)
            XCTAssertNotNil(ProcParsers.parseDarwinLoadavg(sections["loadavg"] ?? ""))
            XCTAssertGreaterThan(ProcParsers.parseDarwinUptime(sections["uptime"] ?? ""), 0)

            let memory = ServerStatus.MemoryInfo(darwinMemory: sections["mem"] ?? "")
            XCTAssertGreaterThan(memory.memTotal, 0)
            XCTAssertGreaterThan(memory.memFree + memory.memCached, 0)
            XCTAssertGreaterThanOrEqual(memory.phyUsed, 0)
            XCTAssertLessThanOrEqual(memory.phyUsed, 1)

            let fileSystem = ServerStatus.FileSystemInfo(dfPk: sections["df"] ?? "")
            XCTAssertTrue(fileSystem.elements.contains { $0.mountPoint == "/" })

            XCTAssertFalse(ProcParsers.parseDarwinNetstat(sections["net"] ?? "").isEmpty)
        }
    }
#endif
