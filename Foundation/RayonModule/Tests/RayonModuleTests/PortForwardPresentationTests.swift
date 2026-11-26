//
//  PortForwardPresentationTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class PortForwardPresentationTests: XCTestCase {
    typealias Lifecycle = PortForwardContext.Lifecycle

    func testConnectInFlightReadsAsConnecting() {
        for state in [Lifecycle.awaitingConnect, .openingChannel] {
            for running in [true, false] {
                let presentation = PortForwardPresentation(state: state, running: running)
                XCTAssertEqual(presentation.status, .running)
                XCTAssertEqual(presentation.text, "Connecting")
            }
        }
    }

    func testForwardRunningFollowsTheSession() {
        var presentation = PortForwardPresentation(state: .forwardRunning, running: true)
        XCTAssertEqual(presentation.status, .success)
        XCTAssertEqual(presentation.text, "Running")

        presentation = PortForwardPresentation(state: .forwardRunning, running: false)
        XCTAssertEqual(presentation.status, .off)
        XCTAssertEqual(presentation.text, "Stopped")
    }

    func testFailuresReadAsDangerWhetherOrNotTheSessionStays() {
        for running in [true, false] {
            var presentation = PortForwardPresentation(state: .failedConnect, running: running)
            XCTAssertEqual(presentation.status, .danger)
            XCTAssertEqual(presentation.text, "Could not connect")

            presentation = PortForwardPresentation(state: .failedAuthenticate, running: running)
            XCTAssertEqual(presentation.status, .danger)
            XCTAssertEqual(presentation.text, "Could not sign in")
        }
    }

    func testForwardStopped() {
        var presentation = PortForwardPresentation(state: .forwardStopped, running: true)
        XCTAssertEqual(presentation.status, .danger)
        XCTAssertEqual(presentation.text, "Forward ended")

        presentation = PortForwardPresentation(state: .forwardStopped, running: false)
        XCTAssertEqual(presentation.status, .off)
        XCTAssertEqual(presentation.text, "Stopped")
    }

    func testTerminatingAndTerminatedReadAsStartingOrStopped() {
        for state in [Lifecycle.terminating, .terminated] {
            var presentation = PortForwardPresentation(state: state, running: true)
            XCTAssertEqual(presentation.status, .running)
            XCTAssertEqual(presentation.text, "Starting")

            presentation = PortForwardPresentation(state: state, running: false)
            XCTAssertEqual(presentation.status, .off)
            XCTAssertEqual(presentation.text, "Stopped")
        }
    }

    func testMissingStateReadsAsStartingOrStopped() {
        var presentation = PortForwardPresentation(state: nil, running: true)
        XCTAssertEqual(presentation.status, .running)
        XCTAssertEqual(presentation.text, "Starting")

        presentation = PortForwardPresentation(state: nil, running: false)
        XCTAssertEqual(presentation.status, .off)
        XCTAssertEqual(presentation.text, "Stopped")
    }

    func testEveryLifecycleStateHasAPresentation() {
        for state in Lifecycle.allCases {
            for running in [true, false] {
                XCTAssertFalse(
                    PortForwardPresentation(state: state, running: running).text.isEmpty,
                    "\(state) needs a word next to the dot"
                )
            }
        }
    }

    func testLifecycleRawValuesRoundTrip() {
        for state in Lifecycle.allCases {
            XCTAssertEqual(Lifecycle(rawValue: state.rawValue), state)
        }
    }
}
