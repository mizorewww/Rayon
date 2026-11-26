//
//  HostKeyTrustTests.swift
//  RayonModuleTests
//
//  A host key is asked about once at a time, and a key turned down is not
//  asked about again.
//

@testable import RayonModule
import os
import RayonSSH
import XCTest

final class HostKeyTrustTests: XCTestCase {
    private final class Asker: HostKeyTrustHandler {
        let answer: Bool
        let asked = OSAllocatedUnfairLock(initialState: 0)
        init(answer: Bool) { self.answer = answer }
        @MainActor func confirm(_: HostKeyQuestion) async -> Bool {
            asked.withLock { $0 += 1 }
            try? await Task.sleep(for: .milliseconds(200))
            return answer
        }
    }

    private var saved: HostKeyTrustHandler?

    override func setUp() { saved = HostKeyTrust.handler }
    override func tearDown() { HostKeyTrust.handler = saved }

    private static func question(_ host: String, key: UInt8 = 1) -> HostKeyQuestion {
        HostKeyQuestion(host: host, port: 22, offered: SSHHostKey(type: "ssh-ed25519", key: Data([key])), saved: nil)
    }

    func testOneQuestionAtATime() async {
        let asker = Asker(answer: true)
        HostKeyTrust.handler = asker
        let host = "concurrent-\(UUID())"
        async let first = HostKeyTrust.confirm(Self.question(host))
        async let second = HostKeyTrust.confirm(Self.question(host))
        let answers = await [first, second]
        XCTAssertEqual(answers, [true, true])
        XCTAssertEqual(asker.asked.withLock { $0 }, 1)
    }

    func testADeclinedKeyIsNotAskedAboutAgain() async {
        let asker = Asker(answer: false)
        HostKeyTrust.handler = asker
        let host = "declined-\(UUID())"
        for _ in 0 ..< 3 {
            let trusted = await HostKeyTrust.confirm(Self.question(host))
            XCTAssertFalse(trusted)
        }
        XCTAssertEqual(asker.asked.withLock { $0 }, 1)
        // Another key, or the same once forgotten, is asked about.
        _ = await HostKeyTrust.confirm(Self.question(host, key: 2))
        XCTAssertEqual(asker.asked.withLock { $0 }, 2)
        HostKeyTrust.forgetDeclined(host: host, port: 22)
        _ = await HostKeyTrust.confirm(Self.question(host))
        XCTAssertEqual(asker.asked.withLock { $0 }, 3)
    }
}
