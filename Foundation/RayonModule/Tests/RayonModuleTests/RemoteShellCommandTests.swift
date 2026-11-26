//
//  RemoteShellCommandTests.swift
//  RayonModuleTests
//
//  An exec channel hands its command to the user's login shell. These run
//  commands the same way, `<shell> -c <command>`, under every login shell
//  this Mac has.
//

#if os(macOS)
    @testable import RayonModule
    import XCTest

    final class RemoteShellCommandTests: XCTestCase {
        private func run(_ command: String, shell: String, home: URL) throws -> (output: String, status: Int32) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", command]
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        }

        /// sh, bash, zsh and csh ship with macOS; fish only when installed.
        private var loginShells: [String] {
            var shells = ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/csh"]
            if let fish = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/usr/bin/fish"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            {
                shells.append(fish)
            }
            return shells.filter { FileManager.default.isExecutableFile(atPath: $0) }
        }

        private func temporaryHome() throws -> URL {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            return home
        }

        func testTheWrapperKeepsQuotesAndDollars() throws {
            let home = try temporaryHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let command = RemoteShellCommand.posix(#"x='it'\''s'; if [ -n "$x" ]; then printf '%s|%s\n' "$x" '$HOME'; fi"#)
            XCTAssertTrue(command.hasPrefix("/bin/sh -c '"))
            for shell in loginShells {
                let result = try run(command, shell: shell, home: home)
                XCTAssertEqual(result.status, 0, shell)
                XCTAssertEqual(result.output, "it's|$HOME\n", shell)
            }
        }

        func testTheKeyInstallsOnceUnderEveryLoginShell() throws {
            let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey o'brien@Rayon"
            let command = PublicKeyDeployment.installCommand(for: key)
            XCTAssertFalse(command.contains("\n"), "csh cannot take a newline inside quotes")
            for shell in loginShells {
                let home = try temporaryHome()
                defer { try? FileManager.default.removeItem(at: home) }
                XCTAssertEqual(try run(command, shell: shell, home: home).status, 0, shell)
                XCTAssertEqual(try run(command, shell: shell, home: home).status, 0, shell)
                let authorized = home.appendingPathComponent(".ssh/authorized_keys")
                XCTAssertEqual(try String(contentsOf: authorized, encoding: .utf8), key + "\n", shell)
                let mode = try FileManager.default.attributesOfItem(atPath: authorized.path)[.posixPermissions] as? Int
                XCTAssertEqual(mode, 0o600, shell)
            }
        }
    }
#endif
