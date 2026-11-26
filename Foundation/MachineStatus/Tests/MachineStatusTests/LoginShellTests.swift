//
//  LoginShellTests.swift
//  MachineStatusTests
//
//  An exec channel hands its command to the user's login shell. These run
//  the monitor's commands the same way, `<shell> -c <command>`, under every
//  login shell this Mac has.
//

#if os(macOS)
    @testable import MachineStatus
    import XCTest

    final class LoginShellTests: XCTestCase {
        private func run(_ command: String, shell: String, locale: String? = nil) throws -> (output: String, status: Int32) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", command]
            var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSTemporaryDirectory()]
            if let locale {
                environment["LANG"] = locale
                environment["LC_ALL"] = locale
            }
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        }

        /// sh, zsh and csh ship with macOS; fish only when installed.
        private var loginShells: [String] {
            var shells = ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/csh"]
            if let fish = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/usr/bin/fish"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            {
                shells.append(fish)
            }
            return shells.filter { FileManager.default.isExecutableFile(atPath: $0) }
        }

        func testTheWrapperKeepsQuotesDollarsAndBangs() throws {
            let script = #"x='it'\''s'; printf '%s|%s|%s\n' "$x" '$HOME' "a!=b""#
            let command = ServerStatus.posixShellCommand(script)
            XCTAssertTrue(command.hasPrefix("/bin/sh -c '"))
            XCTAssertFalse(command.contains("\n"))
            for shell in loginShells {
                let result = try run(command, shell: shell)
                XCTAssertEqual(result.status, 0, shell)
                XCTAssertEqual(result.output, "it's|$HOME|a!=b\n", shell)
            }
        }

        func testTheMonitorCommandRunsUnderEveryLoginShell() throws {
            let command = ServerStatus.monitorCommand(includeStatic: true)
            XCTAssertFalse(command.contains("\n"), "csh cannot take a newline inside quotes")
            for shell in loginShells {
                let result = try run(command, shell: shell)
                XCTAssertEqual(result.status, 0, shell)
                let sections = ProcParsers.splitMonitorSections(result.output)
                XCTAssertEqual(sections["platform"]?.trimmingCharacters(in: .whitespacesAndNewlines), "Darwin", shell)
                XCTAssertEqual(sections["hostname"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, false, shell)
                XCTAssertTrue(ProcParsers.parseDarwinReleaseName(sections["os-release"] ?? "").contains("macOS"), shell)
                XCTAssertGreaterThan(ServerStatus.MemoryInfo(darwinMemory: sections["mem"] ?? "").memTotal, 0, shell)
                let processes = ServerStatus.TopProcessesInfo(cpuSection: sections["procs-cpu"] ?? "", memorySection: sections["procs-mem"] ?? "")
                XCTAssertFalse(processes.byCPU.isEmpty, shell)
                XCTAssertFalse(processes.byMemory.isEmpty, shell)
                XCTAssertNotNil(processes.byMemory.first?.residentKB, shell)
            }
        }

        func testTwoRoundsOnThisMacReadRates() throws {
            let sampler = ServerStatusSampler()
            let command = ServerStatus.monitorCommand(includeStatic: true)
            let first = try run(command, shell: "/bin/sh")
            XCTAssertEqual(sampler.read(first.output, graphicsOutput: nil, clientClock: ProcessInfo.processInfo.systemUptime), .baseline)
            Thread.sleep(forTimeInterval: 1)
            let second = try run(command, shell: "/bin/sh")
            guard case let .status(status) = sampler.read(second.output, graphicsOutput: nil, clientClock: ProcessInfo.processInfo.systemUptime) else {
                return XCTFail("the second round must read")
            }
            XCTAssertGreaterThan(status.processor.summary.sumUsed, 0)
            XCTAssertLessThanOrEqual(status.processor.summary.sumUsed, 100)
            XCTAssertFalse(status.network.elements.isEmpty)
            XCTAssertGreaterThan(status.system.totalProcs, 0)
            XCTAssertGreaterThan(status.system.load1, 0)
            XCTAssertGreaterThan(status.system.uptimeSec, 0)
            XCTAssertTrue(status.system.releaseName.contains("macOS"))
        }

        func testTheMonitorCommandIgnoresTheLoginLocale() throws {
            // A decimal-comma locale must not reach the tools the parsers read.
            let command = ServerStatus.posixShellCommand(ServerStatus.monitorScript(includeStatic: false) + "; locale")
            let result = try run(command, shell: "/bin/sh", locale: "de_DE.UTF-8")
            XCTAssertEqual(result.status, 0)
            let sections = ProcParsers.splitMonitorSections(result.output)
            XCTAssertGreaterThan(ServerStatus.MemoryInfo(darwinMemory: sections["mem"] ?? "").memTotal, 0)
            XCTAssertTrue(ServerStatus.FileSystemInfo(dfPk: sections["df"] ?? "").elements.contains { $0.mountPoint == "/" })
            XCTAssertTrue(result.output.contains("LC_NUMERIC=\"C\""), result.output)
        }

        func testTheGraphicsCommandRunsUnderEveryLoginShell() throws {
            XCTAssertFalse(ServerStatus.graphicsCommand.contains("\n"))
            for shell in loginShells {
                let result = try run(ServerStatus.graphicsCommand, shell: shell)
                XCTAssertEqual(result.status, 0, shell)
                XCTAssertFalse(result.output.isEmpty, shell)
            }
        }

        func testFishIsCoveredWhenInstalled() throws {
            guard loginShells.contains(where: { $0.hasSuffix("/fish") }) else {
                throw XCTSkip("fish is not installed here; the other shells still ran")
            }
        }
    }
#endif
