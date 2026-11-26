//
//  TerminalSplitTests.swift
//  RayonModuleTests
//

@testable import RayonModule
import XCTest

final class TerminalSplitGroupTests: XCTestCase {
    private typealias Group = TerminalManager.SplitGroup

    /// Tabs of four servers, by ID: a split keeps no notion of server.
    private let web = UUID(), db = UUID(), cache = UUID(), local = UUID()

    func testTabsOfDifferentServersShareOneSplit() {
        var groups: [Group] = []
        groups.group(anchorID: web, newID: db, orientation: .horizontal)
        groups.group(anchorID: db, newID: cache, orientation: .grid)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].memberIDs, [web, db, cache])
        XCTAssertEqual(groups[0].orientation, .grid)
        XCTAssertEqual(groups.visiblePaneIDs(focusedID: cache, openIDs: [local, cache, web, db]), [web, db, cache])
    }

    func testATabJoiningLeavesItsOldSplit() {
        var groups: [Group] = []
        groups.group(anchorID: web, newID: db, orientation: .horizontal)
        groups.group(anchorID: cache, newID: local, orientation: .vertical)
        groups.group(anchorID: web, newID: local, orientation: .horizontal, insertBeforeAnchor: true)
        // The cache split had two tabs; with one left, it ends.
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].memberIDs, [local, web, db])
        XCTAssertNil(groups.group(containing: cache))
    }

    func testClosingAPaneKeepsTheRestOfTheSplit() {
        var groups: [Group] = []
        groups.group(anchorID: web, newID: db, orientation: .grid)
        groups.group(anchorID: db, newID: cache, orientation: .grid)
        groups.removeMember(db)
        XCTAssertEqual(groups.first?.memberIDs, [web, cache])
        groups.removeMember(web)
        XCTAssertTrue(groups.isEmpty)
    }

    func testPanesNoLongerOpenAreNotShown() {
        var groups: [Group] = []
        groups.group(anchorID: web, newID: db, orientation: .horizontal)
        XCTAssertEqual(groups.visiblePaneIDs(focusedID: web, openIDs: [web]), [web])
        XCTAssertEqual(groups.visiblePaneIDs(focusedID: cache, openIDs: [web, db, cache]), [cache])
    }

    func testTheOrientationSwitchCyclesThroughTheGrid() {
        XCTAssertEqual(TerminalManager.SplitOrientation.horizontal.next, .vertical)
        XCTAssertEqual(TerminalManager.SplitOrientation.vertical.next, .grid)
        XCTAssertEqual(TerminalManager.SplitOrientation.grid.next, .horizontal)
    }
}

final class SplitGridTests: XCTestCase {
    func testGridDimensionsStayNearlySquare() {
        let expected: [Int: (Int, Int)] = [
            0: (0, 0), 1: (1, 1), 2: (2, 1), 3: (2, 2), 4: (2, 2),
            5: (3, 2), 6: (3, 2), 7: (3, 3), 9: (3, 3), 10: (4, 3), 16: (4, 4), 17: (5, 4),
        ]
        for (count, size) in expected {
            let dims = SplitGrid.dimensions(for: count)
            XCTAssertEqual(dims.columns, size.0, "columns for \(count)")
            XCTAssertEqual(dims.rows, size.1, "rows for \(count)")
            XCTAssertGreaterThanOrEqual(dims.columns * dims.rows, count)
        }
    }

    func testGridRowsFillInOrderWithAShortLastRow() {
        XCTAssertEqual(SplitGrid.rows([1, 2, 3]), [[1, 2], [3]])
        XCTAssertEqual(SplitGrid.rows([1, 2, 3, 4, 5]), [[1, 2, 3], [4, 5]])
        XCTAssertEqual(SplitGrid.rows(Array(1 ... 9)), [[1, 2, 3], [4, 5, 6], [7, 8, 9]])
        XCTAssertEqual(SplitGrid.rows([Int]()), [])
    }
}
