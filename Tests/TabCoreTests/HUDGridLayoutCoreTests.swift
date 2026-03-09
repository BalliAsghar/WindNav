@testable import TabCore
import AppKit
import XCTest

@MainActor
final class HUDGridLayoutCoreTests: XCTestCase {
    func testSelectedTileChromeUsesNeutralFocusPlate() {
        let style = HUDVisualStyle.resolve(appearance: .default).tileChrome(
            isSelected: true,
            thumbnailState: .freshStill,
            showsSubtitle: true
        )

        XCTAssertEqual(style.selectionStyle, .neutralFocusPlate)
        XCTAssertEqual(style.borderWidth, 1)
        XCTAssertGreaterThan(style.backgroundColor.alphaComponent, 0.8)
    }

    func testUnselectedTileChromeUsesMinimalBorderlessTreatment() {
        let style = HUDVisualStyle.resolve(appearance: .default).tileChrome(
            isSelected: false,
            thumbnailState: .freshStill,
            showsSubtitle: true
        )

        XCTAssertEqual(style.selectionStyle, .minimal)
        XCTAssertEqual(style.borderWidth, 0)
        XCTAssertEqual(style.backgroundColor.alphaComponent, 0, accuracy: 0.001)
    }

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
            maximumSize: maximumSize,
            presentationMode: .thumbnails
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
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )

        contentView.frame = CGRect(origin: .zero, size: size)
        contentView.layoutSubtreeIfNeeded()
        contentView.revealSelectedTile()

        XCTAssertGreaterThan(contentView.debugScrollOrigin.y, 0)
    }

    func testTileSuppressesSubtitleWhenLabelMatchesTitle() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 220, height: 160))
        let snapshot = makeSnapshot(index: 0)
        let item = HUDItem(
            id: "1",
            label: "",
            title: "Window 1",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: false,
            thumbnailState: .placeholder
        )

        tile.configure(
            item: item,
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertFalse(tile.debugShowsSubtitle)
    }

    func testTileKeepsStableTitleAndSubtitleFramesWhenSecondaryTextIsMissing() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 220, height: 160))
        let snapshot = makeSnapshot(index: 0)
        let withSubtitle = HUDItem(
            id: "1",
            label: "Ghostty",
            title: "Terminal",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: false,
            thumbnailState: .placeholder
        )
        let withoutSubtitle = HUDItem(
            id: "1",
            label: "",
            title: "Ghostty",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: false,
            thumbnailState: .placeholder
        )

        tile.configure(
            item: withSubtitle,
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        let titleFrameWithSubtitle = tile.debugTitleFrame
        let subtitleFrameWithSubtitle = tile.debugSubtitleFrame
        let iconFrameWithSubtitle = tile.debugIconFrame

        tile.configure(
            item: withoutSubtitle,
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertEqual(tile.debugTitleFrame, titleFrameWithSubtitle)
        XCTAssertEqual(tile.debugSubtitleFrame, subtitleFrameWithSubtitle)
        XCTAssertEqual(tile.debugIconFrame, iconFrameWithSubtitle)
        XCTAssertFalse(tile.debugShowsSubtitle)
    }

    func testTileMetadataAlignmentIsStableAcrossSelectionState() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 220, height: 160))
        let snapshot = makeSnapshot(index: 0)
        let item = HUDItem(
            id: "1",
            label: "Google Chrome",
            title: "YouTube",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: false,
            thumbnailState: .placeholder
        )

        tile.configure(
            item: item,
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        let unselectedTitleFrame = tile.debugTitleFrame
        let unselectedSubtitleFrame = tile.debugSubtitleFrame
        let unselectedIconFrame = tile.debugIconFrame

        tile.configure(
            item: HUDItem(
                id: item.id,
                label: item.label,
                title: item.title,
                pid: item.pid,
                snapshot: item.snapshot,
                isSelected: true,
                thumbnailState: item.thumbnailState
            ),
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertEqual(tile.debugTitleFrame, unselectedTitleFrame)
        XCTAssertEqual(tile.debugSubtitleFrame, unselectedSubtitleFrame)
        XCTAssertEqual(tile.debugIconFrame, unselectedIconFrame)
    }

    func testRelaxedMetricsProvideMoreBreathingRoom() {
        let metrics = HUDGridMetrics(appearance: .default)

        XCTAssertGreaterThanOrEqual(metrics.outerPadding, 18)
        XCTAssertGreaterThanOrEqual(metrics.tileWidth, 144)
        XCTAssertGreaterThanOrEqual(metrics.thumbnailHeight, 82)
    }

    func testIconStripLayoutKeepsSmallSetsOnSingleRow() {
        let metrics = HUDIconStripMetrics(appearance: .default)
        let result = HUDIconStripLayout.layout(
            itemCount: 3,
            metrics: metrics,
            maximumSize: CGSize(width: 900, height: 500)
        )

        XCTAssertEqual(result.tileFrames.count, 3)
        XCTAssertEqual(Set(result.tileFrames.map(\.minY)).count, 1)
        XCTAssertLessThan(result.viewportSize.width, 900)
    }

    func testIconStripRevealScrollsHorizontallyForSelectedTile() {
        let contentView = HUDPanelContentView(frame: .zero)
        let metrics = HUDIconStripMetrics(appearance: .default)
        let maximumSize = CGSize(
            width: metrics.outerPadding * 2 + metrics.tileWidth * 3 + metrics.tileSpacing * 2 + 8,
            height: metrics.tileHeight + metrics.outerPadding * 2
        )
        let size = contentView.apply(
            model: makeModel(count: 8, selectedIndex: 7),
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        contentView.frame = CGRect(origin: .zero, size: size)
        contentView.layoutSubtreeIfNeeded()
        contentView.revealSelectedTile()

        XCTAssertGreaterThan(contentView.debugScrollOrigin.x, 0)
        XCTAssertEqual(contentView.debugScrollOrigin.y, 0, accuracy: 0.01)
    }

    func testIconOnlyViewportIsNotTallerThanThumbnailViewportForSameItemCount() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = sharedMaximumPanelSize()

        let thumbnailSize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let iconOnlySize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        XCTAssertLessThanOrEqual(iconOnlySize.height, thumbnailSize.height)
    }

    func testIconOnlyViewportIsNotWiderThanThumbnailViewportWhenBothFitWithoutScrolling() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = sharedMaximumPanelSize()

        let thumbnailSize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let iconOnlySize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        XCTAssertLessThanOrEqual(iconOnlySize.width, thumbnailSize.width)
    }

    func testTwoItemIconOnlyHudDoesNotExceedThumbnailFootprint() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = sharedMaximumPanelSize()
        let model = makeModel(count: 2, selectedIndex: 1)

        let thumbnailSize = contentView.apply(
            model: model,
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let iconOnlySize = contentView.apply(
            model: model,
            appearance: .default,
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        XCTAssertLessThanOrEqual(iconOnlySize.width, thumbnailSize.width)
        XCTAssertLessThanOrEqual(iconOnlySize.height, thumbnailSize.height)
    }

    func testIconOnlyTileShowsSelectedAppNameOnly() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 126, height: 154))
        let snapshot = makeSnapshot(index: 0)

        tile.configure(
            item: HUDItem(
                id: "1",
                label: "Ghostty",
                title: "Terminal",
                pid: snapshot.pid,
                snapshot: snapshot,
                isSelected: false,
                thumbnailState: .unavailable
            ),
            appearance: .default,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )
        XCTAssertTrue(tile.debugTitleIsHidden)

        tile.configure(
            item: HUDItem(
                id: "1",
                label: "Ghostty",
                title: "Terminal",
                pid: snapshot.pid,
                snapshot: snapshot,
                isSelected: true,
                thumbnailState: .unavailable
            ),
            appearance: .default,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )

        XCTAssertFalse(tile.debugTitleIsHidden)
        XCTAssertEqual(tile.debugTitleString, "Example")
    }

    private func makeModel(count: Int, selectedIndex: Int) -> HUDModel {
        let items = (0..<count).map { index in
            let snapshot = makeSnapshot(index: index)
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

    private func makeSnapshot(index: Int) -> WindowSnapshot {
        WindowSnapshot(
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
    }

    private func makeIconProvider() -> HUDIconProvider {
        HUDIconProvider(source: TestHUDIconSource())
    }

    private func sharedMaximumPanelSize() -> CGSize {
        HUDGridMetrics(appearance: .default).maximumPanelSize(
            for: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
    }
}

@MainActor
private struct TestHUDIconSource: HUDIconSourcing {
    func image(for snapshot: WindowSnapshot) -> NSImage? {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 128, height: 128), xRadius: 24, yRadius: 24).fill()
        image.unlockFocus()
        return image
    }
}
