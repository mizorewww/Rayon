//
//  SSHLiveTests.swift
//  RayonSSHTests
//
//  Against throwaway sshd containers; skipped unless SSH_DOCKER_LIVE is
//  set. Tests/Docker/run-live-tests.sh starts the containers, writes the
//  keys, runs these tests and removes the containers again.
//

import Crypto
import Foundation
import NIOCore
import NIOPosix
import os
@testable import RayonSSH
import XCTest

final class SSHLiveTests: XCTestCase {
    private var keys: URL!
    private var port = 22
    private let user = "rayon"
    private let password = "rayon-password"

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SSH_DOCKER_LIVE"], let port = environment["SSH_DOCKER_LIVE_PORT"].flatMap(Int.init) else {
            throw XCTSkip("Run Tests/Docker/run-live-tests.sh for the live SSH tests")
        }
        keys = URL(fileURLWithPath: directory)
        self.port = port
    }

    private func key(_ name: String, passphrase: String = "") throws -> SSHCredential {
        let text = try String(contentsOf: keys.appendingPathComponent(name), encoding: .utf8)
        return try .privateKey(SSHPrivateKey(text: text, passphrase: passphrase))
    }

    private func connect(
        _ credentials: [SSHCredential],
        username: String? = nil,
        host: String = "127.0.0.1",
        port: Int? = nil,
        transport: SSHTransport = .tcp,
        hostKeyStatus: @escaping @Sendable (SSHHostKey) -> SSHHostKeyStatus = { _ in .trusted }
    ) async throws -> SSHConnection {
        try await SSHConnection.connect(.init(
            host: host,
            port: port ?? self.port,
            username: username ?? user,
            credentials: credentials,
            transport: transport,
            timeout: .seconds(10),
            hostKeyStatus: hostKeyStatus
        ))
    }

    // MARK: Authentication

    func testPassword() async throws {
        let connection = try await connect([.password(password)])
        XCTAssertTrue(connection.serverVersion.hasPrefix("SSH-2.0-OpenSSH"), connection.serverVersion)
        let result = try await connection.execute("whoami")
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "rayon\n")
        await connection.close()
    }

    func testAWrongPasswordIsRejected() async throws {
        do {
            _ = try await connect([.password("wrong")])
            XCTFail("signed in with a wrong password")
        } catch SSHError.authenticationFailed {}
    }

    func testEveryKeyFormat() async throws {
        let cases: [(String, String)] = [
            ("ed25519", ""),
            ("ecdsa", ""),
            ("rsa", ""),
            ("rsa-pem", ""),
            ("ed25519-encrypted", "key-passphrase"),
            ("rsa-encrypted", "key-passphrase"),
            ("ecdsa-encrypted", "key-passphrase"),
            ("rsa-pem-encrypted", "key-passphrase"),
        ]
        for (name, passphrase) in cases {
            let connection = try await connect([key(name, passphrase: passphrase)])
            let result = try await connection.execute("true")
            XCTAssertEqual(result.status, 0, name)
            await connection.close()
        }
    }

    func testAWrongPassphraseIsAClearError() throws {
        XCTAssertThrowsError(try key("ed25519-encrypted", passphrase: "wrong"))
    }

    /// An ssh-agent of this machine's, on a socket of its own, holding
    /// `names`; stopped when the test ends.
    /// Keys in `confirm` must be confirmed for each use, which no one can
    /// here: the agent refuses to sign with them.
    private func agent(holding names: [String], confirm: Set<String> = []) throws -> SSHAgent {
        let socket = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-agent-\(UUID().uuidString.prefix(8))").path
        let daemon = Process()
        daemon.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-agent")
        daemon.arguments = ["-D", "-a", socket]
        // No askpass to confirm with.
        daemon.environment = ["PATH": "/usr/bin:/bin"]
        daemon.standardOutput = FileHandle.nullDevice
        daemon.standardError = FileHandle.nullDevice
        try daemon.run()
        addTeardownBlock {
            daemon.terminate()
            try? FileManager.default.removeItem(atPath: socket)
        }
        for _ in 0 ..< 50 where !FileManager.default.fileExists(atPath: socket) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        for name in names {
            let add = Process()
            add.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
            add.arguments = (confirm.contains(name) ? ["-c"] : []) + ["-q", keys.appendingPathComponent(name).path]
            add.environment = ["SSH_AUTH_SOCK": socket]
            try add.run()
            add.waitUntilExit()
            XCTAssertEqual(add.terminationStatus, 0, name)
        }
        return SSHAgent(socketPath: socket)
    }

    func testTheAgentSignsWithEachKeyType() async throws {
        for name in ["ed25519", "ecdsa", "rsa"] {
            let agent = try agent(holding: [name])
            XCTAssertEqual(try agent.identities().map(\.comment), [name])
            let connection = try await connect([.agent(agent)])
            let result = try await connection.execute("whoami")
            XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "rayon\n", name)
            await connection.close()
        }
    }

    func testTheAgentTriesEveryKeyItHolds() async throws {
        // rsa-unknown is not in authorized_keys; the agent lists it first.
        let agent = try agent(holding: ["rsa-unknown", "ecdsa"])
        XCTAssertEqual(try agent.identities().count, 2)
        let connection = try await connect([.agent(agent)])
        await connection.close()
    }

    /// A key the agent will not sign with (its confirmation declined)
    /// is passed over for the next one.
    func testAKeyTheAgentRefusesIsPassedOver() async throws {
        let agent = try agent(holding: ["rsa-unknown", "ecdsa"], confirm: ["rsa-unknown"])
        let connection = try await connect([.agent(agent)])
        await connection.close()
    }

    /// A server that takes RSA's SHA-512 signatures and turns one down
    /// turned the key down: its SHA-256 and SHA-1 signatures, each another
    /// connection (and another confirmation for an agent key), are not
    /// offered after it.
    func testAnRSAKeyTheServerRefusesCostsOneConnection() async throws {
        let accepted = OSAllocatedUnfairLock(initialState: 0)
        let proxy = try await Self.slowProxy(to: port, delay: .zero) { accepted.withLock { $0 += 1 } }
        defer { proxy.close(promise: nil) }
        let proxied = proxy.localAddress!.port!
        let connection = try await connect([key("rsa-unknown"), key("ed25519")], port: proxied)
        await connection.close()
        XCTAssertEqual(accepted.withLock { $0 }, 2)

        accepted.withLock { $0 = 0 }
        let agent = try agent(holding: ["rsa-unknown", "ecdsa"])
        let viaAgent = try await connect([.agent(agent)], port: proxied)
        await viaAgent.close()
        XCTAssertEqual(accepted.withLock { $0 }, 2)
    }

    /// An agent asking the person first (three seconds here) holds its
    /// own connection only: the others answer meanwhile, and the wait
    /// does not count against signing in, whose timeout is shorter.
    func testAnAgentWaitingForThePersonHoldsNothingElse() async throws {
        let (slow, server) = try await Self.slowAgent(in: agent(holding: ["ecdsa"]), signDelay: .seconds(3))
        defer { server.close(promise: nil) }
        var others: [SSHConnection] = []
        // At least one on every shared event loop.
        for _ in 0 ..< 2 * System.coreCount {
            try await others.append(connect([.password(password)]))
        }
        let configuration = SSHConnection.Configuration(
            host: "127.0.0.1", port: port, username: user, credentials: [.agent(slow)],
            timeout: .seconds(2), hostKeyStatus: { _ in .trusted }
        )
        let signing = Task { try await SSHConnection.connect(configuration) }
        try await Task.sleep(for: .seconds(1))
        let slowest = try await withThrowingTaskGroup(of: Duration.self) { group in
            for other in others {
                group.addTask {
                    let started = ContinuousClock.now
                    _ = try await other.execute("true")
                    return ContinuousClock.now - started
                }
            }
            return try await group.reduce(Duration.zero) { max($0, $1) }
        }
        XCTAssertLessThan(slowest, .seconds(1), "another connection waited for the agent")
        let connection = try await signing.value
        await connection.close()
        for other in others { await other.close() }
    }

    /// Asking a slow agent for its keys blocks no thread Swift concurrency
    /// runs everything else on.
    func testListingTheAgentsKeysBlocksNoTask() async throws {
        let (slow, server) = try await Self.slowAgent(in: agent(holding: ["ecdsa"]), signDelay: .seconds(2), type: 11)
        defer { server.close(promise: nil) }
        let configuration = SSHConnection.Configuration(
            host: "127.0.0.1", port: port, username: user, credentials: [.agent(slow)], hostKeyStatus: { _ in .trusted }
        )
        let signingIn = (0 ..< System.coreCount + 1).map { _ in Task { try await SSHConnection.connect(configuration) } }
        try await Task.sleep(for: .milliseconds(500))
        let started = ContinuousClock.now
        await Task.detached {}.value
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(500), "a task waited for the agent")
        // That many sign-ins at once go past sshd's MaxStartups: some are dropped.
        for task in signingIn { if let connection = try? await task.value { await connection.close() } }
    }

    func testAnEmptyOrMissingAgent() async throws {
        do {
            _ = try await connect([.agent(agent(holding: []))])
            XCTFail("signed in with no key")
        } catch let SSHError.agentUnavailable(reason) {
            // Not authenticationFailed: the server was never asked, so the
            // app still checks whether it can be reached.
            XCTAssertEqual(reason, "The SSH agent holds no keys.")
        }
        do {
            _ = try await connect([.agent(SSHAgent(socketPath: "/nonexistent/agent.sock"))])
            XCTFail("signed in with no agent")
        } catch let SSHError.agentUnavailable(reason) {
            XCTAssertTrue(reason.contains("/nonexistent/agent.sock"), reason)
        }
    }

    func testAKeyIsTriedAfterAPasswordTheServerRefuses() async throws {
        let connection = try await connect([.password("wrong"), key("ed25519")])
        await connection.close()
    }

    // MARK: Host keys

    func testAnUnknownHostKeyStopsWithItsFingerprint() async throws {
        let line = try String(contentsOf: keys.appendingPathComponent("host_ed25519.pub"), encoding: .utf8)
        let blob = try XCTUnwrap(Data(base64Encoded: String(line.split(separator: " ")[1])))
        let expected = SSHHostKey(type: "ssh-ed25519", key: blob)
        do {
            _ = try await connect([.password(password)], hostKeyStatus: { _ in .unknown })
            XCTFail("connected without trusting the key")
        } catch let SSHError.unknownHostKey(key) {
            XCTAssertEqual(key, expected)
            XCTAssertEqual(key.fingerprint, expected.fingerprint)
        }
    }

    func testAChangedHostKeyIsRefused() async throws {
        let saved = SSHHostKey(type: "ssh-ed25519", key: Data(repeating: 7, count: 51))
        do {
            _ = try await connect([.password(password)], hostKeyStatus: { _ in .changed(saved: saved) })
            XCTFail("connected to a changed key")
        } catch let SSHError.hostKeyChanged(offered, previous) {
            XCTAssertEqual(previous, saved)
            XCTAssertNotEqual(offered, saved)
        }
    }

    // MARK: Commands

    func testExitStatuses() async throws {
        let connection = try await connect([.password(password)])
        let ok = try await connection.execute("echo out; echo err >&2")
        XCTAssertEqual(ok.status, 0)
        XCTAssertEqual(String(decoding: ok.output, as: UTF8.self), "out\n")
        XCTAssertEqual(String(decoding: ok.errorOutput, as: UTF8.self), "err\n")
        let three = try await connection.execute("exit 3")
        XCTAssertEqual(three.status, 3)
        let started = Date()
        do {
            _ = try await connection.execute("sleep 30", timeout: .seconds(1))
            XCTFail("a command past its timeout succeeded")
        } catch SSHError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        }
        do {
            _ = try await connection.execute("kill -9 $$")
            XCTFail("a killed command succeeded")
        } catch SSHError.channelRejected {}
        // The connection outlives a timed-out command.
        let after = try await connection.execute("echo still")
        XCTAssertEqual(String(decoding: after.output, as: UTF8.self), "still\n")
        await connection.close()
    }

    /// A command (a snippet run included) has no terminal: pagers, sudo
    /// prompts and `[ -t 1 ]` rc files would wait on one for input.
    func testACommandRunsWithoutATerminal() async throws {
        let connection = try await connect([.password(password)])
        let result = try await connection.execute("[ -t 0 ] || [ -t 1 ] && echo terminal || echo none")
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "none\n")
        await connection.close()
    }

    /// A stopped command ends on the server by the SIGTERM of the signal
    /// request: without a terminal, closing the channel alone would leave
    /// it running. The trap proves the TERM reached the command.
    func testAStoppedCommandEndsOnTheServer() async throws {
        let connection = try await connect([.password(password)])
        let marker = "/tmp/rayon-got-term-\(UUID().uuidString)"
        for (command, sleeper) in [
            ("sleep 120", "sleep 120"),
            ("trap 'touch \(marker); kill $!; exit' TERM; sleep 121 & wait", "sleep 121"),
        ] {
            let run = Task { try await connection.execute(command) { _, _ in } }
            var running = ""
            for _ in 0 ..< 50 where running.isEmpty {
                try await Task.sleep(for: .milliseconds(100))
                running = try await String(decoding: connection.execute("pgrep -fx '\(sleeper)'").output, as: UTF8.self)
            }
            XCTAssertFalse(running.isEmpty, "\(sleeper) never started")
            run.cancel()
            _ = try? await run.value
            var left = running
            for _ in 0 ..< 50 where !left.isEmpty {
                try await Task.sleep(for: .milliseconds(100))
                left = try await String(decoding: connection.execute("pgrep -fx '\(sleeper)'").output, as: UTF8.self)
            }
            XCTAssertEqual(left, "", "\(sleeper) outlived its stop")
        }
        let trapped = try await connection.execute("test -e \(marker) && rm \(marker)").status
        XCTAssertEqual(trapped, 0, "the command never got SIGTERM")
        await connection.close()
    }

    // MARK: Shell

    func testShellEchoesAndResizes() async throws {
        let connection = try await connect([.password(password)])
        let shell = try await connection.openShell(terminalType: "xterm-256color", columns: 80, rows: 24)
        let (input, typing) = AsyncStream<ByteBuffer>.makeStream()
        let screen = Screen()
        let run = Task { try await shell.run(input: input) { await screen.append($0) } }

        typing.yield(ByteBuffer(string: "stty size; echo MARK-$((20+22))\n"))
        try await screen.wait(for: "24 80")
        try await screen.wait(for: "MARK-42")
        shell.resize(columns: 132, rows: 50)
        try await Task.sleep(for: .milliseconds(300))
        typing.yield(ByteBuffer(string: "stty size\n"))
        try await screen.wait(for: "50 132")
        typing.yield(ByteBuffer(string: "exit 5\n"))
        let status = try await run.value
        XCTAssertEqual(status, 5)
        await connection.close()
    }

    /// Input pasted while the remote floods output and reads none must not
    /// freeze the session: output keeps being read while input waits for
    /// window, so neither side waits on the other for good.
    func testPastingIntoAFloodingProgramDoesNotDeadlock() async throws {
        let connection = try await connect([.password(password)])
        let shell = try await connection.openShell(terminalType: "xterm-256color", columns: 120, rows: 40)
        let (input, typing) = AsyncStream<ByteBuffer>.makeStream()
        let screen = Screen()
        let run = Task { try await shell.run(input: input) { await screen.append($0) } }
        typing.yield(ByteBuffer(string: "stty raw -echo; echo READY-$((1+1)); yes | head -c 20000000; cat > /dev/null & sleep 3; kill $!; stty sane; echo; echo DONE-$((40+2))\n"))
        try await screen.wait(for: "READY-2", timeout: 30)
        typing.yield(ByteBuffer(repeating: UInt8(ascii: "x"), count: 4_000_000))
        try await screen.wait(for: "DONE-42", timeout: 120)
        typing.finish()
        shell.close()
        _ = try? await run.value
        await connection.close()
    }

    // MARK: Closing under a flood

    // A channel this side closes while the server is still sending: the
    // data that arrives before the server's close must not make
    // swift-nio-ssh adjust the window of a channel it already closed.

    func testCancellingAFloodingCommand() async throws {
        let connection = try await connect([.password(password)])
        for _ in 0 ..< 20 {
            let started = Task { try await connection.execute("yes") { _, _ in } }
            try await Task.sleep(for: .milliseconds(200))
            started.cancel()
            _ = try? await started.value
        }
        let after = try await connection.execute("echo still")
        XCTAssertEqual(String(decoding: after.output, as: UTF8.self), "still\n")
        await connection.close()
    }

    func testAFloodingCommandThatTimesOut() async throws {
        let connection = try await connect([.password(password)])
        for _ in 0 ..< 20 {
            do {
                _ = try await connection.execute("yes", timeout: .milliseconds(300)) { _, _ in }
                XCTFail("a flood past its timeout succeeded")
            } catch SSHError.timedOut {}
        }
        let after = try await connection.execute("echo still")
        XCTAssertEqual(String(decoding: after.output, as: UTF8.self), "still\n")
        await connection.close()
    }

    func testClosingAFloodingShell() async throws {
        let connection = try await connect([.password(password)])
        for _ in 0 ..< 20 {
            let shell = try await connection.openShell(terminalType: "xterm", columns: 80, rows: 24)
            let (input, typing) = AsyncStream<ByteBuffer>.makeStream()
            let screen = Screen()
            let run = Task { try await shell.run(input: input) { await screen.append($0) } }
            typing.yield(ByteBuffer(string: "echo FLOOD-$((1+1)); yes\n"))
            try await screen.wait(for: "FLOOD-2")
            try await Task.sleep(for: .milliseconds(100))
            shell.close()
            typing.finish()
            _ = try? await run.value
        }
        let after = try await connection.execute("echo still")
        XCTAssertEqual(String(decoding: after.output, as: UTF8.self), "still\n")
        await connection.close()
    }

    func testClosingAConnectionWhileChildrenFlood() async throws {
        for _ in 0 ..< 10 {
            let connection = try await connect([.password(password)])
            let shell = try await connection.openShell(terminalType: "xterm", columns: 80, rows: 24)
            let (input, typing) = AsyncStream<ByteBuffer>.makeStream()
            let run = Task { try await shell.run(input: input) { _ in } }
            typing.yield(ByteBuffer(string: "yes\n"))
            let commands = (0 ..< 3).map { _ in Task { try await connection.execute("yes") { _, _ in } } }
            try await Task.sleep(for: .milliseconds(300))
            await connection.close()
            typing.finish()
            _ = try? await run.value
            for command in commands { _ = try? await command.value }
        }
    }

    /// A finished channel waits for the server to confirm its close; a
    /// connection that ends first closes it with an error, which must not
    /// fail its closeFuture (NIOAsyncChannel asserts it never fails).
    func testClosingAConnectionWhileAChannelWaitsForItsClose() async throws {
        for _ in 0 ..< 10 {
            let connection = try await connect([.password(password)])
            let channel = try await connection.openDirectTCPIP(host: "127.0.0.1", port: 9001)
            try await channel.executeThenClose { inbound, outbound in
                for try await _ in inbound {}
                outbound.finish()
                connection.channel.close(promise: nil)
            }
        }
    }

    // MARK: SFTP

    func testUploadsKeepTheirPermissions() async throws {
        let connection = try await connect([.password(password)])
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-modes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        for (name, mode) in [("tool.sh", 0o755), ("secret", 0o600)] {
            let file = local.appendingPathComponent(name)
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: local.path)

        try await sftp.upload(local, toDirectory: "/tmp") { _ in }
        let remote = "/tmp/" + local.lastPathComponent
        let modes = try await Dictionary(uniqueKeysWithValues: sftp.entries(at: remote).map { ($0.name, $0.permissions.map { $0 & 0o777 }) })
        XCTAssertEqual(modes, ["tool.sh": 0o755, "secret": 0o600])
        let folder = try await sftp.entry(at: remote)
        XCTAssertEqual(folder.permissions.map { $0 & 0o777 }, 0o700)
        await connection.close()
    }

    /// A read-only folder still takes its contents, and a read-only file
    /// can be uploaded again; both keep their modes.
    func testReadOnlyUploads() async throws {
        let connection = try await connect([.password(password)])
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-readonly-\(UUID().uuidString)")
        let file = local.appendingPathComponent("a.txt")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: local.path)
        let remote = "/tmp/" + local.lastPathComponent
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: local.path)
            try? FileManager.default.removeItem(at: local)
        }

        func mode(_ path: String) async throws -> UInt32? {
            try await sftp.entry(at: path).permissions.map { $0 & 0o777 }
        }
        try await sftp.upload(local, toDirectory: "/tmp") { _ in }
        var folderMode = try await mode(remote), fileMode = try await mode(remote + "/a.txt")
        XCTAssertEqual(folderMode, 0o555)
        XCTAssertEqual(fileMode, 0o444)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: local.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try Data("second".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        try await sftp.upload(file, toDirectory: remote) { _ in }
        let written = try await connection.execute("cat \(remote)/a.txt")
        XCTAssertEqual(String(decoding: written.output, as: UTF8.self), "second")
        fileMode = try await mode(remote + "/a.txt")
        folderMode = try await mode(remote)
        XCTAssertEqual(fileMode, 0o444)
        XCTAssertEqual(folderMode, 0o555)
        _ = try await connection.execute("chmod -R u+w \(remote) && rm -rf \(remote)")
        await connection.close()
    }

    /// A folder holding a link back to itself is uploaded once; a link to
    /// a file is copied as the file.
    func testUploadsDoNotFollowLinksToFolders() async throws {
        let connection = try await connect([.password(password)])
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        try Data("x".utf8).write(to: local.appendingPathComponent("file"))
        try FileManager.default.createSymbolicLink(atPath: local.appendingPathComponent("self").path, withDestinationPath: ".")
        try FileManager.default.createSymbolicLink(atPath: local.appendingPathComponent("alias").path, withDestinationPath: "file")

        try await sftp.upload(local, toDirectory: "/tmp") { _ in }
        let remote = "/tmp/" + local.lastPathComponent
        let names = try await Set(sftp.entries(at: remote).map(\.name))
        XCTAssertEqual(names, ["file", "alias"])
        _ = try await connection.execute("rm -rf \(remote)")
        await connection.close()
    }

    func testDownloadsDoNotFollowLinksToFolders() async throws {
        let connection = try await connect([.password(password)])
        let made = try await connection.execute("""
        rm -rf /tmp/links && mkdir -p /tmp/links/deep && cd /tmp/links && echo hi > note && \
        ln -s . self && ln -s .. up && ln -s note note-link && ln -s missing dangling && ln -s ../.. deep/top
        """)
        XCTAssertEqual(made.status, 0, String(decoding: made.errorOutput, as: UTF8.self))
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-links-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: local) }

        try await sftp.download("/tmp/links", to: local) { _ in }
        let copied = try FileManager.default.subpathsOfDirectory(atPath: local.path).sorted()
        XCTAssertEqual(copied, ["deep", "note", "note-link"])
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("note-link"), encoding: .utf8), "hi\n")

        _ = try await connection.execute("mkdir -p /tmp/nested/" + Array(repeating: "d", count: 33).joined(separator: "/"))
        do {
            try await sftp.download("/tmp/nested", to: local.appendingPathComponent("nested")) { _ in }
            XCTFail("downloaded 33 folders deep")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("32 folders deep"), error.localizedDescription)
        }
        await connection.close()
    }

    /// With 25 ms each way, one 32 KB request per round trip would take
    /// over six seconds for 4 MB.
    func testSFTPKeepsRequestsInFlight() async throws {
        let proxy = try await Self.slowProxy(to: port, delay: .milliseconds(25))
        defer { proxy.close(promise: nil) }
        let connection = try await connect([.password(password)], port: proxy.localAddress!.port!)
        _ = try await connection.execute("head -c 4000000 /dev/urandom > /tmp/big")
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-big-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }

        var started = ContinuousClock.now
        try await sftp.download("/tmp/big", to: local.appendingPathComponent("big")) { _ in }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2.5), "download")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: local.appendingPathComponent("big").path)[.size] as? Int, 4_000_000)

        _ = try await connection.execute("mkdir -p /tmp/back")
        started = ContinuousClock.now
        try await sftp.upload(local.appendingPathComponent("big"), toDirectory: "/tmp/back") { _ in }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2.5), "upload")
        let same = try await connection.execute("cmp /tmp/big /tmp/back/big")
        XCTAssertEqual(same.status, 0, String(decoding: same.output, as: UTF8.self))
        await connection.close()
    }

    /// A link full of terminal output still opens channels, though the
    /// server's confirmation queues behind the output for longer than the
    /// connection's timeout.
    func testAChannelOpensBehindABusyLink() async throws {
        let proxy = try await Self.slowProxy(to: port, delay: .zero, downBytesPerSecond: 200_000)
        defer { proxy.close(promise: nil) }
        let connection = try await SSHConnection.connect(.init(
            host: "127.0.0.1", port: proxy.localAddress!.port!, username: user, credentials: [.password(password)],
            timeout: .seconds(5), hostKeyStatus: { _ in .trusted }
        ))
        let flood = Task { try await connection.execute("head -c 40000000 /dev/zero") { _, _ in } }
        try await Task.sleep(for: .seconds(4))
        let result = try await connection.execute("true")
        XCTAssertEqual(result.status, 0)
        flood.cancel()
        await connection.close()
    }

    /// An upload that fails part way (the server's 1 MB /small fills up)
    /// leaves what arrived in order, never a file with a hole of zeros.
    func testAFailedUploadLeavesNoHole() async throws {
        let connection = try await connect([.password(password)])
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-full-\(UUID().uuidString)")
        try Data(repeating: 0x61, count: 3_000_000).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        for _ in 0 ..< 5 {
            do {
                try await sftp.upload(local, toDirectory: "/small") { _ in }
                XCTFail("3 MB fit into 1 MB")
            } catch {}
            let check = try await connection.execute("wc -c < /small/\(local.lastPathComponent); tr -d a < /small/\(local.lastPathComponent) | wc -c; rm /small/\(local.lastPathComponent)")
            let numbers = String(decoding: check.output, as: UTF8.self).split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            XCTAssertEqual(numbers.count, 2)
            XCTAssertEqual(numbers.last, 0, "bytes other than the file's in the \(numbers.first ?? 0) bytes left")
        }
        await connection.close()
    }

    func testSFTPListUploadDownload() async throws {
        let connection = try await connect([.password(password)])
        let sftp = try await connection.openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-sftp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }
        let folder = local.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = Data((0 ..< 300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try payload.write(to: folder.appendingPathComponent("blob.bin"))
        try Data("hello".utf8).write(to: folder.appendingPathComponent("note.txt"))

        try await sftp.upload(folder, toDirectory: "/tmp") { _ in }
        let entries = try await sftp.entries(at: "/tmp/folder")
        XCTAssertEqual(Set(entries.map(\.name)), ["blob.bin", "note.txt"])
        XCTAssertEqual(entries.first { $0.name == "blob.bin" }?.size, Int64(payload.count))
        let folderEntry = try await sftp.entry(at: "/tmp/folder")
        XCTAssertTrue(folderEntry.isDirectory)

        let back = local.appendingPathComponent("back")
        try await sftp.download("/tmp/folder", to: back) { _ in }
        XCTAssertEqual(try Data(contentsOf: back.appendingPathComponent("blob.bin")), payload)

        try await sftp.rename("/tmp/folder/note.txt", to: "/tmp/folder/renamed.txt")
        try await sftp.removeItem(at: "/tmp/folder") { _ in }
        do {
            _ = try await sftp.entries(at: "/tmp/folder")
            XCTFail("the folder is still there")
        } catch {}
        await sftp.close()
        await connection.close()
    }

    // MARK: Forwarding

    /// 100 MB through `ssh -L` to an echo service, read back slowly, so the
    /// SSH window and the sockets have to hold the sender back.
    func testLocalForwardCarries100MBUnderBackpressure() async throws {
        let connection = try await connect([.password(password)])
        let bindPort = try Self.freePort()
        let listener = try await SSHForwardListener.local(port: bindPort, targetHost: "127.0.0.1", targetPort: 9000)
        let forward = Task { try await connection.runForward(listener) }
        let total = 100 * 1024 * 1024
        let (sent, received) = try await Self.echo(total: total, through: bindPort, slowReader: true)
        XCTAssertEqual(received, sent)
        forward.cancel()
        await connection.close()
    }

    /// The pull-based stream the VNC client reads: a burst of several MB
    /// (a full frame) arrives whole, however it is chunked.
    func testByteStreamCarriesAMultiMegabyteBurst() async throws {
        let connection = try await connect([.password(password)])
        let stream = try await connection.openByteStream(host: "127.0.0.1", port: 9000)
        let burst = (0 ..< 12 * 1024 * 1024).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 13) }
        stream.send(ByteBuffer(bytes: burst))
        var received = [UInt8]()
        received.reserveCapacity(burst.count)
        while received.count < burst.count {
            let chunk = try await stream.receive(maximumLength: 64 * 1024)
            XCTAssertLessThanOrEqual(chunk.readableBytes, 64 * 1024)
            received += chunk.readableBytesView
        }
        XCTAssertEqual(received, burst)
        stream.close()
        do {
            _ = try await stream.receive(maximumLength: 1)
            XCTFail("a closed stream still reads")
        } catch SSHError.disconnected {}
        await connection.close()
    }

    /// The terminal, files, commands and a tunnel share one connection.
    func testChannelsShareOneConnection() async throws {
        let connection = try await connect([.password(password)])
        let shell = try await connection.openShell(terminalType: "xterm", columns: 80, rows: 24)
        let sftp = try await connection.openSFTP()
        async let listing = sftp.entries(at: "/")
        async let commands = withThrowingTaskGroup(of: Int32.self) { group in
            for code in 0 ..< 8 { group.addTask { try await connection.execute("exit \(code)").status } }
            return try await group.reduce(into: [Int32]()) { $0.append($1) }.sorted()
        }
        let (entries, statuses) = try await (listing, commands)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(statuses, Array(0 ..< 8))
        shell.close()
        await sftp.close()
        await connection.close()
    }

    // MARK: A server that stops answering

    /// Freezes the server container (its kernel still answers TCP) until
    /// the test ends.
    private func freezeServer() throws {
        guard let server = ProcessInfo.processInfo.environment["SSH_DOCKER_LIVE_SERVER"] else {
            throw XCTSkip("needs the server container's name")
        }
        func docker(_ arguments: String...) throws {
            let docker = Process()
            docker.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
            docker.arguments = arguments
            try docker.run()
            docker.waitUntilExit()
        }
        try docker("pause", server)
        addTeardownBlock { try? docker("unpause", server) }
    }

    func testAServerThatStopsAnsweringIsDropped() async throws {
        let connection = try await SSHConnection.connect(.init(
            host: "127.0.0.1", port: port, username: user, credentials: [.password(password)],
            timeout: .seconds(10), keepAliveInterval: .seconds(1), hostKeyStatus: { _ in .trusted }
        ))
        _ = try await connection.execute("true")
        let running = Task { try await connection.execute("sleep 60") }
        try await Task.sleep(for: .milliseconds(300))
        try freezeServer()

        let started = ContinuousClock.now
        while connection.isActive, ContinuousClock.now - started < .seconds(15) {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(connection.isActive, "still active after the server froze")
        // Four quiet seconds: three unanswered asks, then the close.
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(8))
        do {
            _ = try await running.value
            XCTFail("a command finished on a frozen server")
        } catch {}
        do {
            _ = try await connection.execute("true")
            XCTFail("a command ran on a closed connection")
        } catch SSHError.disconnected {}
    }

    /// An account that may run no command (ForceCommand internal-sftp)
    /// still answers the keepalive's ask; only a frozen server does not.
    func testAnAccountThatRunsNoCommandStillAnswers() async throws {
        let connection = try await connect([.password(password)], username: "sftponly")
        let ran = try? await connection.execute("exit", timeout: .seconds(2))
        XCTAssertNotEqual(ran?.status, 0, "the account ran a command")
        let answers = await connection.answers(within: .seconds(5))
        XCTAssertTrue(answers)
        try freezeServer()
        let started = ContinuousClock.now
        let frozenAnswers = await connection.answers(within: .seconds(2))
        XCTAssertFalse(frozenAnswers)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(4))
        await connection.close()
    }

    func testOpeningAChannelOnAFrozenServerEnds() async throws {
        let connection = try await connect([.password(password)])
        _ = try await connection.execute("true")
        try freezeServer()

        let started = ContinuousClock.now
        do {
            _ = try await connection.execute("true", timeout: .seconds(2))
            XCTFail("a command ran on a frozen server")
        } catch SSHError.channelRejected {}
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(4))

        let opening = Task { try await connection.execute("true") }
        try await Task.sleep(for: .milliseconds(500))
        opening.cancel()
        do {
            _ = try await opening.value
            XCTFail("a command ran on a frozen server")
        } catch is CancellationError {}
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(6))
        await connection.close()
    }

    /// A service that hangs up first: this side's EOF after the server's
    /// closes the channel instead of breaking swift-nio-ssh's state.
    func testAServerThatHangsUpFirst() async throws {
        let connection = try await connect([.password(password)])
        for _ in 0 ..< 20 {
            let channel = try await connection.openDirectTCPIP(host: "127.0.0.1", port: 9001)
            let greeting = try await channel.executeThenClose { inbound, outbound in
                var text = ""
                for try await chunk in inbound { text += String(buffer: chunk) }
                outbound.finish()
                return text
            }
            XCTAssertEqual(greeting, "hello\n")
        }
        await connection.close()
    }

    func testDynamicForwardSpeaksSOCKS5() async throws {
        let connection = try await connect([.password(password)])
        let bindPort = try Self.freePort()
        let listener = try await SSHForwardListener.dynamic(port: bindPort)
        let forward = Task { try await connection.runForward(listener) }
        let client = try await Self.dial(port: bindPort)
        try await client.executeThenClose { inbound, outbound in
            var reader = inbound.makeAsyncIterator()
            try await outbound.write(ByteBuffer(bytes: [5, 1, 0]))
            var reply = try await Self.read(2, from: &reader)
            XCTAssertEqual(Array(reply.readableBytesView), [5, 0])
            let host = Array("localhost".utf8)
            try await outbound.write(ByteBuffer(bytes: [5, 1, 0, 3, UInt8(host.count)] + host + [0x23, 0x28]))
            reply = try await Self.read(10, from: &reader)
            XCTAssertEqual(reply.getInteger(at: 1, as: UInt8.self), 0, "the CONNECT succeeds")
            try await outbound.write(ByteBuffer(string: "through socks"))
            let echoed = try await Self.read(13, from: &reader)
            XCTAssertEqual(String(buffer: echoed), "through socks")
        }
        forward.cancel()
        await connection.close()
    }

    func testRemoteForwardReachesThisSide() async throws {
        let connection = try await connect([.password(password)])
        // A one-shot service on this side that answers with a greeting.
        let service = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                }
            }
        let servicePort = try XCTUnwrap(service.channel.localAddress?.port)
        let serving = Task {
            try await service.executeThenClose { clients in
                for try await client in clients {
                    try await client.executeThenClose { _, outbound in
                        try await outbound.write(ByteBuffer(string: "hello from here\n"))
                    }
                }
            }
        }
        let listening = expectation(description: "listening")
        let forward = Task {
            try await connection.runRemoteForward(bindPort: 9100, targetHost: "127.0.0.1", targetPort: servicePort) {
                listening.fulfill()
            }
        }
        await fulfillment(of: [listening], timeout: 10)
        let result = try await connection.execute("socat -T 3 - TCP:127.0.0.1:9100 </dev/null", timeout: .seconds(10))
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "hello from here\n")
        forward.cancel()
        serving.cancel()
        await connection.close()
    }

    // MARK: ProxyJump

    func testProxyJumpReachesAServerOnlyTheBastionSees() async throws {
        let bastion = try await connect([.password(password)])
        let target = try await connect([key("ed25519")], host: "target", port: 22, transport: .jump(bastion))
        let result = try await target.execute("hostname")
        let bastionName = try await bastion.execute("hostname")
        XCTAssertEqual(result.status, 0)
        XCTAssertNotEqual(result.output, bastionName.output, "the command ran on the target")
        await target.close()
        // Closing the jumped connection closes the bastion it rode on.
        try await bastion.closed.get()
    }

    func testAFailedJumpClosesTheBastion() async throws {
        let refused = try await connect([.password(password)])
        do {
            _ = try await connect([.password("wrong")], host: "target", port: 22, transport: .jump(refused))
            XCTFail("signed in with a wrong password")
        } catch SSHError.authenticationFailed {}
        try await refused.closed.get()
    }

    /// The target is unreachable from the bastion; the sign-in waits on it.
    func testACancelledJumpEndsAndClosesTheBastion() async throws {
        let waiting = try await connect([.password(password)])
        let configuration = SSHConnection.Configuration(
            host: "10.255.255.1", port: 22, username: user, credentials: [.password(password)],
            transport: .jump(waiting), timeout: .seconds(60), hostKeyStatus: { _ in .trusted }
        )
        let connecting = Task { try await SSHConnection.connect(configuration) }
        try await Task.sleep(for: .milliseconds(500))
        let cancelled = ContinuousClock.now
        connecting.cancel()
        _ = await connecting.result
        try await waiting.closed.get()
        XCTAssertLessThan(ContinuousClock.now - cancelled, .seconds(2))
    }

    // MARK: Helpers

    private actor Screen {
        private var text = ""

        func append(_ chunk: ByteBuffer) {
            text += String(decoding: chunk.readableBytesView, as: UTF8.self)
            // utf8.count is O(1); count walks every character.
            if text.utf8.count > 1_000_000 { text = String(text.suffix(4096)) }
        }

        func contains(_ marker: String) -> Bool { text.contains(marker) }

        nonisolated func wait(for marker: String, timeout: TimeInterval = 10) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while await !contains(marker) {
                guard Date() < deadline else { throw SSHError.timedOut }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// A TCP proxy to the server on a port of its own that holds what
    /// passes, either way, for `delay`: a link with a round trip.
    private static func slowProxy(
        to port: Int,
        delay: TimeAmount,
        downBytesPerSecond: Int? = nil,
        accepted: @escaping @Sendable () -> Void = {}
    ) async throws -> Channel {
        /// Holds what passes for `delay`, and at most `rate` bytes a second.
        final class Delay: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer
            let peer: Channel
            let delay: TimeAmount
            let rate: Int?
            var free = NIODeadline.now()
            init(peer: Channel, delay: TimeAmount, rate: Int? = nil) { self.peer = peer; self.delay = delay; self.rate = rate }
            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let bytes = unwrapInboundIn(data)
                let peer = peer
                free = max(free, .now() + delay)
                if let rate { free = free + .nanoseconds(Int64(bytes.readableBytes) * 1_000_000_000 / Int64(rate)) }
                context.eventLoop.scheduleTask(deadline: free) { peer.writeAndFlush(bytes, promise: nil) }
            }
            func channelInactive(context: ChannelHandlerContext) {
                let peer = peer
                context.eventLoop.scheduleTask(deadline: max(free, .now() + delay)) { peer.close(promise: nil) }
            }
        }
        return try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { inbound in
                accepted()
                return ClientBootstrap(group: inbound.eventLoop)
                    .channelInitializer { outbound in
                        outbound.eventLoop.makeCompletedFuture {
                            try outbound.pipeline.syncOperations.addHandler(Delay(peer: inbound, delay: delay, rate: downBytesPerSecond))
                        }
                    }
                    .connect(host: "127.0.0.1", port: port)
                    .flatMapThrowing { outbound in
                        try inbound.pipeline.syncOperations.addHandler(Delay(peer: outbound, delay: delay))
                    }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
    }

    /// An agent in front of `agent` that passes sign requests (or the
    /// requests of `type`: 11 lists the keys) on only after `signDelay`,
    /// as one asking for a confirmation does.
    private static func slowAgent(in agent: SSHAgent, signDelay: TimeAmount, type: UInt8 = 13) async throws -> (SSHAgent, Channel) {
        final class Relay: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer
            let peer: Channel
            let signDelay: TimeAmount
            let type: UInt8
            init(peer: Channel, signDelay: TimeAmount, type: UInt8 = 0) { self.peer = peer; self.signDelay = signDelay; self.type = type }
            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let bytes = unwrapInboundIn(data)
                let peer = peer
                // A request's type follows its four-byte length.
                let delay = bytes.getInteger(at: bytes.readerIndex + 4, as: UInt8.self) == type ? signDelay : .zero
                context.eventLoop.scheduleTask(in: delay) { peer.writeAndFlush(bytes, promise: nil) }
            }
            func channelInactive(context: ChannelHandlerContext) {
                peer.close(promise: nil)
            }
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rayon-slow-\(UUID().uuidString.prefix(8))").path
        let upstream = agent.socketPath
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { inbound in
                ClientBootstrap(group: inbound.eventLoop)
                    .channelInitializer { outbound in
                        outbound.eventLoop.makeCompletedFuture {
                            try outbound.pipeline.syncOperations.addHandler(Relay(peer: inbound, signDelay: .zero))
                        }
                    }
                    .connect(unixDomainSocketPath: upstream)
                    .flatMapThrowing { outbound in
                        try inbound.pipeline.syncOperations.addHandler(Relay(peer: outbound, signDelay: signDelay, type: type))
                    }
            }
            .bind(unixDomainSocketPath: path, cleanupExistingSocketFile: true)
            .get()
        return (SSHAgent(socketPath: path), server)
    }

    private static func freePort() throws -> Int {
        let channel = try ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).bind(host: "127.0.0.1", port: 0).wait()
        defer { try? channel.close().wait() }
        return channel.localAddress!.port!
    }

    private static func dial(port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .connect(host: "127.0.0.1", port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(
                        wrappingChannelSynchronously: channel, configuration: .init(isOutboundHalfClosureEnabled: true)
                    )
                }
            }
    }

    private static func read(
        _ count: Int,
        from reader: inout NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
    ) async throws -> ByteBuffer {
        var collected = ByteBuffer()
        while collected.readableBytes < count {
            guard var chunk = try await reader.next() else { throw SSHError.disconnected }
            collected.writeBuffer(&chunk)
        }
        return collected
    }

    /// Writes `total` pseudo-random bytes and reads the echo back, slowly
    /// when asked; returns the digests of both.
    private static func echo(total: Int, through port: Int, slowReader: Bool) async throws -> (String, String) {
        let client = try await dial(port: port)
        return try await client.executeThenClose { inbound, outbound in
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    var hash = SHA256()
                    var generator = SystemRandomNumberGenerator()
                    var left = total
                    while left > 0 {
                        let size = min(left, 64 * 1024)
                        let bytes = (0 ..< size / 8).flatMap { _ in withUnsafeBytes(of: generator.next() as UInt64) { Array($0) } }
                        hash.update(data: bytes)
                        try await outbound.write(ByteBuffer(bytes: bytes))
                        left -= size
                    }
                    outbound.finish()
                    return "sent " + hash.finalize().description
                }
                group.addTask {
                    var hash = SHA256()
                    var count = 0
                    var chunks = 0
                    for try await chunk in inbound {
                        hash.update(data: Array(chunk.readableBytesView))
                        count += chunk.readableBytes
                        chunks += 1
                        // A reader that falls behind now and then.
                        if slowReader, chunks % 200 == 0 { try await Task.sleep(for: .milliseconds(20)) }
                        if count >= total { break }
                    }
                    XCTAssertEqual(count, total)
                    return "received " + hash.finalize().description
                }
                var sent = "", received = ""
                for try await digest in group {
                    if digest.hasPrefix("sent ") { sent = String(digest.dropFirst(5)) } else { received = String(digest.dropFirst(9)) }
                }
                return (sent, received)
            }
        }
    }
}
