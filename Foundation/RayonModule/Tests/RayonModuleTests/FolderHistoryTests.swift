//
//  FolderHistoryTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class FolderHistoryTests: XCTestCase {
    func testNewHistoryGoesNowhere() {
        var history = FolderHistory()
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        XCTAssertNil(history.goBack(from: "/"))
        XCTAssertNil(history.goForward(from: "/"))
        XCTAssertEqual(history, FolderHistory(), "a move that goes nowhere changes nothing")
    }

    func testBackAndForwardRetraceTheFolders() {
        var history = FolderHistory()
        history.visit(from: "/", to: "/var")
        history.visit(from: "/var", to: "/var/log")
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)

        XCTAssertEqual(history.goBack(from: "/var/log"), "/var")
        XCTAssertEqual(history.goBack(from: "/var"), "/")
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.goForward(from: "/"), "/var")
        XCTAssertEqual(history.goForward(from: "/var"), "/var/log")
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back, ["/", "/var"])
    }

    func testGoingSomewhereNewForgetsWhatWasAhead() {
        var history = FolderHistory()
        history.visit(from: "/", to: "/var")
        history.visit(from: "/var", to: "/var/log")
        _ = history.goBack(from: "/var/log")
        XCTAssertTrue(history.canGoForward)

        history.visit(from: "/var", to: "/etc")
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back, ["/", "/var"])
    }

    func testStayingInTheSameFolderIsNoStep() {
        var history = FolderHistory()
        history.visit(from: "/var", to: "/var/log")
        _ = history.goBack(from: "/var/log")
        history.visit(from: "/var", to: "/var")
        XCTAssertEqual(history.back, [])
        XCTAssertEqual(history.forward, ["/var/log"], "a reload keeps what is ahead")
    }

    func testOnlyTheLatestFoldersAreKept() {
        var history = FolderHistory()
        for index in 0 ... FolderHistory.limit {
            history.visit(from: "/\(index)", to: "/\(index + 1)")
        }
        XCTAssertEqual(history.back.count, FolderHistory.limit)
        XCTAssertEqual(history.back.first, "/1")
        XCTAssertEqual(history.back.last, "/\(FolderHistory.limit)")
    }

    func testContextWithoutAConnectionKeepsItsHistory() {
        let context = FileTransferContext(
            machine: RDMachine(remoteAddress: "10.0.0.1", remotePort: "22", name: "alpha")
        )
        context.navigate(path: "/var")
        XCTAssertFalse(context.canGoBack, "a folder that could not be shown is not a step")
        context.goBack()
        context.goForward()
        XCTAssertEqual(context.history, FolderHistory())
    }
}
