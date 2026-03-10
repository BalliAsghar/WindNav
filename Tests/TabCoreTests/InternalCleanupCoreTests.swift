@testable import TabCore
import Foundation
import XCTest

final class InternalCleanupCoreTests: XCTestCase {
    func testSyntheticWindowIDRoundTripsPID() {
        let pid: pid_t = 4242
        let synthetic = SyntheticWindowID.make(pid: pid)

        XCTAssertTrue(SyntheticWindowID.matches(windowId: synthetic, pid: pid))
        XCTAssertFalse(SyntheticWindowID.matches(windowId: synthetic - 1, pid: pid))
    }

    func testWrappedIndexHandlesNegativeAndOverflowValues() {
        XCTAssertEqual(WindowSnapshotSupport.wrappedIndex(-1, count: 3), 2)
        XCTAssertEqual(WindowSnapshotSupport.wrappedIndex(3, count: 3), 0)
        XCTAssertEqual(WindowSnapshotSupport.wrappedIndex(0, count: 0), 0)
    }

    func testSnapshotFilteringAndWindowlessOrderingPreserveRules() {
        let snapshots: [WindowSnapshot] = [
            .init(
                windowId: 1,
                pid: 101,
                bundleId: "com.apple.finder",
                appName: "Finder",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Finder",
                isWindowlessApp: true
            ),
            .init(
                windowId: 2,
                pid: 102,
                bundleId: "com.example.hidden",
                appName: "Hidden",
                frame: .zero,
                isMinimized: false,
                appIsHidden: true,
                isFullscreen: false,
                title: "Hidden"
            ),
            .init(
                windowId: 3,
                pid: 103,
                bundleId: "com.example.notes",
                appName: "Notes",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Notes"
            ),
            .init(
                windowId: 4,
                pid: 104,
                bundleId: "com.example.empty",
                appName: "Empty",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Empty",
                isWindowlessApp: true
            ),
        ]

        let filtered = WindowSnapshotSupport.applyFilters(
            snapshots,
            visibility: .init(
                showMinimized: true,
                showHidden: false,
                showFullscreen: true,
                showEmptyApps: .showAtEnd
            ),
            filters: .default
        )

        XCTAssertEqual(filtered.map(\.windowId), [3, 4])

        let reordered = WindowSnapshotSupport.applyWindowlessOrdering(
            filtered.reversed(),
            showEmptyApps: .showAtEnd
        )
        XCTAssertEqual(reordered.map(\.windowId), [3, 4])
    }

    func testSnapshotSortAndLabelHelpersProduceStableResults() {
        let alpha = WindowSnapshot(
            windowId: 20,
            pid: 200,
            bundleId: "com.example.alpha",
            appName: "Alpha",
            frame: .zero,
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "B"
        )
        let beta = WindowSnapshot(
            windowId: 10,
            pid: 100,
            bundleId: "com.example.beta",
            appName: "Beta",
            frame: .zero,
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "A"
        )

        let sorted = [beta, alpha].sorted(by: WindowSnapshotSupport.snapshotSortOrder(lhs:rhs:))
        XCTAssertEqual(sorted.map(\.windowId), [20, 10])
        XCTAssertEqual(WindowSnapshotSupport.appLabel(for: [alpha]), "Alpha")

        let bundleOnly = WindowSnapshot(
            windowId: 30,
            pid: 300,
            bundleId: "com.example.bundle",
            appName: nil,
            frame: .zero,
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: nil
        )
        XCTAssertEqual(WindowSnapshotSupport.appLabel(for: [bundleOnly]), "com.example.bundle")
    }

    func testHUDModelFactoryBuildsBadgesForRepeatedAppWindows() {
        let windows: [WindowSnapshot] = [
            .init(
                windowId: 1,
                pid: 500,
                bundleId: "com.example.app",
                appName: "Example",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "One"
            ),
            .init(
                windowId: 2,
                pid: 500,
                bundleId: "com.example.app",
                appName: "Example",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Two",
                isWindowlessApp: true
            ),
        ]

        let model = HUDModelFactory.makeModel(
            windows: windows,
            selectedIndex: 1,
            appearance: .default,
            hud: .default
        )

        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.items.map(\.windowIndexInApp), [1, 2])
        XCTAssertEqual(model.items.map(\.isSelected), [false, true])
        XCTAssertEqual(model.items.map(\.isWindowlessApp), [false, true])
        XCTAssertEqual(model.items.map(\.label), ["", ""])
    }
}
