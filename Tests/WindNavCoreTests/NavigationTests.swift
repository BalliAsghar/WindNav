import CoreGraphics
@testable import WindNavCore
import XCTest

@MainActor
final class NavigationTests: XCTestCase {
    func testRightMovesToNextWindowInRing() {
        let navigator = LogicalCycleNavigator()
        let windows = [snapshot(id: 10), snapshot(id: 20), snapshot(id: 30)]
        let focused = windows[1]

        let result = navigator.target(from: focused, direction: .right, orderedCandidates: windows)

        XCTAssertEqual(result?.windowId, 30)
    }

    func testLeftMovesToPreviousWindowInRing() {
        let navigator = LogicalCycleNavigator()
        let windows = [snapshot(id: 10), snapshot(id: 20), snapshot(id: 30)]
        let focused = windows[1]

        let result = navigator.target(from: focused, direction: .left, orderedCandidates: windows)

        XCTAssertEqual(result?.windowId, 10)
    }

    func testWrapAroundAtRingBoundaries() {
        let navigator = LogicalCycleNavigator()
        let windows = [snapshot(id: 10), snapshot(id: 20), snapshot(id: 30)]

        let rightWrapped = navigator.target(from: windows[2], direction: .right, orderedCandidates: windows)
        let leftWrapped = navigator.target(from: windows[0], direction: .left, orderedCandidates: windows)

        XCTAssertEqual(rightWrapped?.windowId, 10)
        XCTAssertEqual(leftWrapped?.windowId, 30)
    }

    func testSingleCandidateReturnsNil() {
        let navigator = LogicalCycleNavigator()
        let only = snapshot(id: 10)

        let result = navigator.target(from: only, direction: .right, orderedCandidates: [only])

        XCTAssertNil(result)
    }

    func testMRUSyncSeedsUnseenWindowsInAscendingOrder() {
        let store = MRUWindowOrderStore()
        store.syncVisibleWindowIDs([30, 10, 20])

        XCTAssertEqual(store.orderedIDs(within: [10, 20, 30]), [10, 20, 30])
    }

    func testMRUPromoteMovesWindowToFront() {
        let store = MRUWindowOrderStore()
        store.syncVisibleWindowIDs([10, 20, 30])
        store.promote(20)

        XCTAssertEqual(store.orderedIDs(within: [10, 20, 30]), [20, 10, 30])
    }

    func testMRUSyncPrunesClosedWindows() {
        let store = MRUWindowOrderStore()
        store.syncVisibleWindowIDs([10, 20, 30])
        store.promote(30)
        store.syncVisibleWindowIDs([10, 30])

        XCTAssertEqual(store.orderedIDs(within: [10, 30]), [30, 10])
    }

    func testCycleSessionReusesFrozenOrderWithinTimeout() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let candidateSet: Set<UInt32> = [10, 20, 30]
        let first = CycleSessionResolver.resolve(
            existing: nil,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0,
            timeoutMs: 900,
            freshOrderedWindowIDs: [10, 20, 30]
        )

        let second = CycleSessionResolver.resolve(
            existing: first.state,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0.addingTimeInterval(0.2),
            timeoutMs: 900,
            freshOrderedWindowIDs: [30, 20, 10]
        )

        XCTAssertTrue(second.reusedSession)
        XCTAssertNil(second.resetReason)
        XCTAssertEqual(second.orderedWindowIDs, [10, 20, 30])
    }

    func testCycleSessionResetsOnTimeout() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let candidateSet: Set<UInt32> = [10, 20, 30]
        let first = CycleSessionResolver.resolve(
            existing: nil,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0,
            timeoutMs: 900,
            freshOrderedWindowIDs: [10, 20, 30]
        )

        let second = CycleSessionResolver.resolve(
            existing: first.state,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0.addingTimeInterval(1.2),
            timeoutMs: 900,
            freshOrderedWindowIDs: [30, 20, 10]
        )

        XCTAssertFalse(second.reusedSession)
        XCTAssertEqual(second.resetReason, .timeout)
        XCTAssertEqual(second.orderedWindowIDs, [30, 20, 10])
    }

    func testCycleSessionDoesNotResetWhenTimeoutDisabled() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let candidateSet: Set<UInt32> = [10, 20, 30]
        let first = CycleSessionResolver.resolve(
            existing: nil,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0,
            timeoutMs: 0,
            freshOrderedWindowIDs: [10, 20, 30]
        )

        let second = CycleSessionResolver.resolve(
            existing: first.state,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0.addingTimeInterval(10),
            timeoutMs: 0,
            freshOrderedWindowIDs: [30, 20, 10]
        )

        XCTAssertTrue(second.reusedSession)
        XCTAssertNil(second.resetReason)
        XCTAssertEqual(second.orderedWindowIDs, [10, 20, 30])
    }

    func testCycleSessionResetsOnMonitorChange() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let candidateSet: Set<UInt32> = [10, 20]
        let first = CycleSessionResolver.resolve(
            existing: nil,
            monitorID: 1,
            candidateSet: candidateSet,
            now: t0,
            timeoutMs: 900,
            freshOrderedWindowIDs: [10, 20]
        )

        let second = CycleSessionResolver.resolve(
            existing: first.state,
            monitorID: 2,
            candidateSet: candidateSet,
            now: t0.addingTimeInterval(0.1),
            timeoutMs: 900,
            freshOrderedWindowIDs: [20, 10]
        )

        XCTAssertEqual(second.resetReason, .monitorChanged)
        XCTAssertEqual(second.orderedWindowIDs, [20, 10])
    }

    func testCycleSessionResetsOnCandidateSetChange() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let first = CycleSessionResolver.resolve(
            existing: nil,
            monitorID: 1,
            candidateSet: [10, 20, 30],
            now: t0,
            timeoutMs: 900,
            freshOrderedWindowIDs: [10, 20, 30]
        )

        let second = CycleSessionResolver.resolve(
            existing: first.state,
            monitorID: 1,
            candidateSet: [10, 20],
            now: t0.addingTimeInterval(0.1),
            timeoutMs: 900,
            freshOrderedWindowIDs: [20, 10]
        )

        XCTAssertEqual(second.resetReason, .candidateSetChanged)
        XCTAssertEqual(second.orderedWindowIDs, [20, 10])
    }

    private func snapshot(id: UInt32) -> WindowSnapshot {
        WindowSnapshot(
            windowId: id,
            pid: 1,
            bundleId: "com.example",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false,
            appIsHidden: false,
            title: "w\(id)"
        )
    }
}
