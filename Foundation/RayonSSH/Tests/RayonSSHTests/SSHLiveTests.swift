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
        host: String = "127.0.0.1",
        port: Int? = nil,
        transport: SSHTransport = .tcp,
        hostKeyStatus: @escaping @Sendable (SSHHostKey) -> SSHHostKeyStatus = { _ in .trusted }
    ) async throws -> SSHConnection {
        try await SSHConnection.connect(.init(
            host: host,
            port: port ?? self.port,
            username: user,
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

    // MARK: SFTP

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
        let listening = expectation(description: "listening")
        let forward = Task {
            try await connection.runLocalForward(bindPort: bindPort, targetHost: "127.0.0.1", targetPort: 9000) {
                listening.fulfill()
            }
        }
        await fulfillment(of: [listening], timeout: 10)
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
        let listening = expectation(description: "listening")
        let forward = Task {
            try await connection.runDynamicForward(bindPort: bindPort) { listening.fulfill() }
        }
        await fulfillment(of: [listening], timeout: 10)
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

    // MARK: Helpers

    private actor Screen {
        private var text = ""

        func append(_ chunk: ByteBuffer) {
            text += String(decoding: chunk.readableBytesView, as: UTF8.self)
            if text.count > 1_000_000 { text = String(text.suffix(4096)) }
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
