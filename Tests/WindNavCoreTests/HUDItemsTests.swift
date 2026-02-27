import CoreGraphics
@testable import WindNavCore
import XCTest

final class HUDItemsTests: XCTestCase {
    func testHUDOverlayAnchorMappingForTopCenterUsesBottom() {
        XCTAssertEqual(hudOverlayAnchor(for: .topCenter), .bottom)
    }

    func testHUDOverlayAnchorMappingForMiddleCenterUsesTop() {
        XCTAssertEqual(hudOverlayAnchor(for: .middleCenter), .top)
    }

    func testHUDOverlayAnchorMappingForBottomCenterUsesTop() {
        XCTAssertEqual(hudOverlayAnchor(for: .bottomCenter), .top)
    }

    func testHUDOutsideBandInsetsForTopCenterUseBottomBand() {
        let insets = hudOutsideBandInsets(for: .topCenter, bandHeight: 40)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.bottom, 40)
    }

    func testHUDOutsideBandInsetsForMiddleCenterUseTopBand() {
        let insets = hudOutsideBandInsets(for: .middleCenter, bandHeight: 40)
        XCTAssertEqual(insets.top, 40)
        XCTAssertEqual(insets.bottom, 0)
    }

    func testHUDOutsideBandInsetsForBottomCenterUseTopBand() {
        let insets = hudOutsideBandInsets(for: .bottomCenter, bandHeight: 40)
        XCTAssertEqual(insets.top, 40)
        XCTAssertEqual(insets.bottom, 0)
    }

    func testHUDVerticalPositionCompensationForMiddleCenter() {
        XCTAssertEqual(hudVerticalPositionCompensation(for: .middleCenter, bandHeight: 40), 20)
    }

    func testHUDVerticalPositionCompensationForTopAndBottomCenter() {
        XCTAssertEqual(hudVerticalPositionCompensation(for: .topCenter, bandHeight: 40), 0)
        XCTAssertEqual(hudVerticalPositionCompensation(for: .bottomCenter, bandHeight: 40), 0)
    }

    func testBuildCycleHUDItemsUsesStableAppRingKeysAsIDs() {
        let terminalGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Terminal", pid: 101),
            label: "Terminal",
            windows: [snapshot(windowId: 10, pid: 101, bundleId: "com.apple.Terminal", x: 0, y: 0)],
            isPinned: true
        )
        let safariGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Safari", pid: 202),
            label: "Safari",
            windows: [snapshot(windowId: 20, pid: 202, bundleId: "com.apple.Safari", x: 20, y: 0)],
            isPinned: false
        )

        let first = buildCycleHUDItems(groups: [terminalGroup, safariGroup], selectedIndex: 0, selectedWindowID: 10)
        let second = buildCycleHUDItems(groups: [terminalGroup, safariGroup], selectedIndex: 1, selectedWindowID: 20)

        XCTAssertEqual(first.map(\.id), ["bundle:com.apple.Terminal", "bundle:com.apple.Safari"])
        XCTAssertEqual(second.map(\.id), ["bundle:com.apple.Terminal", "bundle:com.apple.Safari"])
    }

    func testBuildCycleHUDItemsComputesCurrentWindowIndexUsingSpatialOrder() {
        let selectedGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Terminal", pid: 101),
            label: "Terminal",
            windows: [
                snapshot(windowId: 30, pid: 101, bundleId: "com.apple.Terminal", x: 100, y: 40),
                snapshot(windowId: 20, pid: 101, bundleId: "com.apple.Terminal", x: 0, y: 40),
                snapshot(windowId: 10, pid: 101, bundleId: "com.apple.Terminal", x: 0, y: 10),
            ],
            isPinned: true
        )
        let otherGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Safari", pid: 202),
            label: "Safari",
            windows: [snapshot(windowId: 40, pid: 202, bundleId: "com.apple.Safari", x: 10, y: 10)],
            isPinned: false
        )

        let items = buildCycleHUDItems(groups: [selectedGroup, otherGroup], selectedIndex: 0, selectedWindowID: 20)

        XCTAssertEqual(items[0].windowCount, 3)
        XCTAssertEqual(items[0].currentWindowIndex, 1)
        XCTAssertNil(items[1].currentWindowIndex)
    }

    func testBuildCycleHUDItemsSupportsNoSelectedApp() {
        let terminalGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Terminal", pid: 101),
            label: "Terminal",
            windows: [snapshot(windowId: 10, pid: 101, bundleId: "com.apple.Terminal", x: 0, y: 0)],
            isPinned: true
        )
        let safariGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Safari", pid: 202),
            label: "Safari",
            windows: [snapshot(windowId: 20, pid: 202, bundleId: "com.apple.Safari", x: 20, y: 0)],
            isPinned: false
        )

        let items = buildCycleHUDItems(
            groups: [terminalGroup, safariGroup],
            selectedIndex: nil,
            selectedWindowID: nil
        )

        XCTAssertEqual(items.map(\.isCurrent), [false, false])
        XCTAssertEqual(items.map(\.currentWindowIndex), [nil, nil])
    }

    func testBuildCycleHUDItemsFallsBackToFirstWindowWhenSelectedWindowMissing() {
        let selectedGroup = AppRingGroup(
            key: AppRingKey(bundleId: "com.apple.Terminal", pid: 101),
            label: "Terminal",
            windows: [
                snapshot(windowId: 10, pid: 101, bundleId: "com.apple.Terminal", x: 0, y: 0),
                snapshot(windowId: 20, pid: 101, bundleId: "com.apple.Terminal", x: 40, y: 0),
            ],
            isPinned: true
        )
        let items = buildCycleHUDItems(
            groups: [selectedGroup],
            selectedIndex: 0,
            selectedWindowID: 999
        )

        XCTAssertEqual(items[0].windowCount, 2)
        XCTAssertEqual(items[0].currentWindowIndex, 0)
    }

    private func snapshot(windowId: UInt32, pid: pid_t, bundleId: String?, x: CGFloat, y: CGFloat) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: bundleId,
            frame: CGRect(x: x, y: y, width: 100, height: 100),
            isMinimized: false,
            appIsHidden: false,
            title: nil
        )
    }
}
