@testable import TabCore
import AppKit
import XCTest

@MainActor
final class HUDGridLayoutCoreTests: XCTestCase {
    func testGridLayoutKeepsSmallSetsOnOneRowAndShrinksWidth() {
        let metrics = HUDGridMetrics(appearance: .default)
        let result = HUDGridLayout.layout(
            itemCount: 3,
            metrics: metrics,
            maximumSize: CGSize(width: 900, height: 500)
        )

        XCTAssertEqual(result.rows.count, 1)
        XCTAssertLessThan(result.viewportSize.width, 900)
        XCTAssertEqual(result.tileFrames.count, 3)
    }

    func testGridLayoutWrapsBeforeExceedingWidthCap() {
        let metrics = HUDGridMetrics(appearance: .default)
        let maximumWidth = metrics.outerPadding * 2
            + metrics.tileWidth * 3
            + metrics.tileSpacing * 2
            + 8
        let result = HUDGridLayout.layout(
            itemCount: 7,
            metrics: metrics,
            maximumSize: CGSize(width: maximumWidth, height: 500)
        )

        XCTAssertEqual(result.rows.count, 3)
        XCTAssertLessThanOrEqual(result.viewportSize.width, maximumWidth)
    }

    func testGridLayoutCentersShortFinalRow() {
        let metrics = HUDGridMetrics(appearance: .default)
        let maximumWidth = metrics.outerPadding * 2
            + metrics.tileWidth * 4
            + metrics.tileSpacing * 3
            + 8
        let result = HUDGridLayout.layout(
            itemCount: 7,
            metrics: metrics,
            maximumSize: CGSize(width: maximumWidth, height: 500)
        )

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertGreaterThan(result.rows[1].frame.minX, metrics.outerPadding)
    }

    func testContentViewPreferredSizeShrinksForSmallWindowSets() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = CGSize(width: 900, height: 500)
        let size = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            maximumSize: maximumSize
        )

        XCTAssertLessThan(size.width, maximumSize.width)
    }

    func testSelectedTileRevealScrollsForLowerRows() {
        let contentView = HUDPanelContentView(frame: .zero)
        let metrics = HUDGridMetrics(appearance: .default)
        let maximumSize = CGSize(
            width: metrics.outerPadding * 2 + metrics.tileWidth * 3 + metrics.tileSpacing * 2 + 8,
            height: metrics.tileHeight + metrics.outerPadding * 2 + 4
        )
        let size = contentView.apply(
            model: makeModel(count: 8, selectedIndex: 7),
            appearance: .default,
            maximumSize: maximumSize
        )

        contentView.frame = CGRect(origin: .zero, size: size)
        contentView.layoutSubtreeIfNeeded()
        contentView.revealSelectedTile()

        XCTAssertGreaterThan(contentView.debugScrollOrigin.y, 0)
    }

    private func makeModel(count: Int, selectedIndex: Int) -> HUDModel {
        let items = (0..<count).map { index in
            let snapshot = WindowSnapshot(
                windowId: UInt32(index + 1),
                pid: 100 + Int32(index),
                bundleId: "com.example.\(index)",
                appName: "Example",
                frame: CGRect(x: 0, y: 0, width: 1200, height: 700),
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Window \(index + 1)",
                revision: UInt64(index + 1)
            )
            return HUDItem(
                id: "\(index + 1)",
                label: index.isMultiple(of: 2) ? "Example" : "Window \(index + 1)",
                title: "Window \(index + 1)",
                pid: snapshot.pid,
                snapshot: snapshot,
                isSelected: index == selectedIndex,
                thumbnailState: .placeholder
            )
        }
        return HUDModel(items: items, selectedIndex: selectedIndex)
    }
}
