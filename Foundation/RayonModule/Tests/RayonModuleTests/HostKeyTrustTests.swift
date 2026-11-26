//
//  HostKeyTrustTests.swift
//  RayonModuleTests
//
//  A host key is asked about once at a time; a key turned down is not
//  asked about again by a reconnect nobody asked for, and a question
//  nobody answered is no "no".
//

@testable import RayonModule
import os
import RayonSSH
import XCTest

final class HostKeyTrustTests: XCTestCase {
    private final class Asker: HostKeyTrustHandler {
        let answer: HostKeyAnswer
        let asked = OSAllocatedUnfairLock(initialState: 0)
        init(answer: HostKeyAnswer) { self.answer = answer }
        @MainActor func confirm(_: HostKeyQuestion) async -> HostKeyAnswer {
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
        let asker = Asker(answer: .trusted)
        HostKeyTrust.handler = asker
        let host = "concurrent-\(UUID())"
        async let first = HostKeyTrust.confirm(Self.question(host), background: false)
        async let second = HostKeyTrust.confirm(Self.question(host), background: true)
        let answers = await [first, second]
        XCTAssertEqual(answers, [true, true])
        XCTAssertEqual(asker.asked.withLock { $0 }, 1)
    }

    func testADeclinedKeyIsNotAskedAboutAgainInTheBackground() async {
        let asker = Asker(answer: .declined)
        HostKeyTrust.handler = asker
        let host = "declined-\(UUID())"
        for _ in 0 ..< 3 {
            let trusted = await HostKeyTrust.confirm(Self.question(host), background: true)
            XCTAssertFalse(trusted)
        }
        XCTAssertEqual(asker.asked.withLock { $0 }, 1)
        // Another key, the person connecting again, or the key forgotten
        // is asked about.
        _ = await HostKeyTrust.confirm(Self.question(host, key: 2), background: true)
        XCTAssertEqual(asker.asked.withLock { $0 }, 2)
        _ = await HostKeyTrust.confirm(Self.question(host), background: false)
        XCTAssertEqual(asker.asked.withLock { $0 }, 3)
        HostKeyTrust.forgetDeclined(host: host, port: 22)
        _ = await HostKeyTrust.confirm(Self.question(host), background: true)
        XCTAssertEqual(asker.asked.withLock { $0 }, 4)
    }

    /// A question that could not be shown, or went away unanswered, was
    /// never turned down.
    func testAnUnansweredQuestionIsAskedAgain() async {
        let asker = Asker(answer: .unanswered)
        HostKeyTrust.handler = asker
        let host = "unanswered-\(UUID())"
        for _ in 0 ..< 2 {
            let trusted = await HostKeyTrust.confirm(Self.question(host), background: true)
            XCTAssertFalse(trusted)
        }
        XCTAssertEqual(asker.asked.withLock { $0 }, 2)
    }
}
