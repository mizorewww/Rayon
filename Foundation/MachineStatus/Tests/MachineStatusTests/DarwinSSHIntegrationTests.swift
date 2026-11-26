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

            let processor = ServerStatus.ProcessorInfo(darwinTop: sections["darwin-top"])
            XCTAssertNotNil(processor)
            XCTAssertGreaterThanOrEqual(processor?.summary.sumUsed ?? -1, 0)
            XCTAssertLessThanOrEqual(processor?.summary.sumUsed ?? 101, 100)

            let load = ProcParsers.parseDarwinTopLoad(sections["darwin-top"] ?? "")
            XCTAssertGreaterThan(load.totalProcess, 0)
            XCTAssertGreaterThanOrEqual(load.load1avg, 0)
            XCTAssertGreaterThan(ProcParsers.parseDarwinUptime(sections["uptime"] ?? ""), 0)

            let memory = ServerStatus.MemoryInfo(darwinMemory: sections["mem"] ?? "")
            XCTAssertGreaterThan(memory.memTotal, 0)
            XCTAssertGreaterThan(memory.memFree + memory.memCached, 0)
            XCTAssertGreaterThanOrEqual(memory.phyUsed, 0)
            XCTAssertLessThanOrEqual(memory.phyUsed, 1)

            let fileSystem = ServerStatus.FileSystemInfo(dfPk: sections["df"] ?? "")
            XCTAssertTrue(fileSystem.elements.contains { $0.mountPoint == "/" })

            let network = ServerStatus.NetworkInfo(netstatBefore: sections["net-a"], netstatAfter: sections["net-b"])
            XCTAssertEqual(network?.elements.isEmpty, false)
        }
    }
#endif
