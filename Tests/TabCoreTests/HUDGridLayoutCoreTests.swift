@testable import TabCore
import AppKit
import XCTest

@MainActor
final class HUDGridLayoutCoreTests: XCTestCase {
    private let defaultHUD = HUDConfig.default

    func testSelectedTileChromeUsesNeutralFocusPlate() {
        let style = HUDVisualStyle.resolve(appearance: .default).tileChrome(
            isSelected: true,
            thumbnailState: .freshStill
        )

        XCTAssertEqual(style.selectionStyle, .neutralFocusPlate)
        XCTAssertEqual(style.borderWidth, 3)
        XCTAssertEqual(style.backgroundColor.alphaComponent, 0.2, accuracy: 0.01)
    }

    func testUnselectedTileChromeUsesMinimalBorderlessTreatment() {
        let style = HUDVisualStyle.resolve(appearance: .default).tileChrome(
            isSelected: false,
            thumbnailState: .freshStill
        )

        XCTAssertEqual(style.selectionStyle, .minimal)
        XCTAssertEqual(style.borderWidth, 0)
        XCTAssertEqual(style.backgroundColor.alphaComponent, 0, accuracy: 0.001)
    }

    func testGridLayoutKeepsSmallSetsOnOneRowAndShrinksWidth() {
        let metrics = HUDGridMetrics(appearance: .default, hud: defaultHUD)
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
        let metrics = HUDGridMetrics(appearance: .default, hud: defaultHUD)
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
        let metrics = HUDGridMetrics(appearance: .default, hud: defaultHUD)
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
            hud: defaultHUD,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )

        XCTAssertLessThan(size.width, maximumSize.width)
    }

    func testPanelChromeUsesSofterTintAndShadowInThumbnailMode() {
        let contentView = HUDPanelContentView(frame: .zero)

        _ = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            hud: defaultHUD,
            maximumSize: CGSize(width: 900, height: 500),
            presentationMode: .thumbnails
        )

        XCTAssertLessThan(contentView.debugTintColor.alphaComponent, 0.16)
        XCTAssertLessThan(contentView.debugPanelShadowOpacity, 0.2)
        XCTAssertLessThan(contentView.debugPanelShadowRadius, 18)
    }

    func testPanelChromeUsesSofterTintAndShadowInIconOnlyMode() {
        let contentView = HUDPanelContentView(frame: .zero)

        _ = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            hud: defaultHUD,
            maximumSize: CGSize(width: 900, height: 500),
            presentationMode: .iconOnly
        )

        XCTAssertLessThan(contentView.debugTintColor.alphaComponent, 0.13)
        XCTAssertLessThan(contentView.debugPanelShadowOpacity, 0.16)
        XCTAssertLessThan(contentView.debugPanelShadowRadius, 16)
    }

    func testSelectedTileRevealScrollsForLowerRows() {
        let contentView = HUDPanelContentView(frame: .zero)
        let metrics = HUDGridMetrics(appearance: .default, hud: defaultHUD)
        let maximumSize = CGSize(
            width: metrics.outerPadding * 2 + metrics.tileWidth * 3 + metrics.tileSpacing * 2 + 8,
            height: metrics.tileHeight + metrics.outerPadding * 2 + 4
        )
        let size = contentView.apply(
            model: makeModel(count: 8, selectedIndex: 7),
            appearance: .default,
            hud: defaultHUD,
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
            hud: defaultHUD,
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
            hud: defaultHUD,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        let titleFrameWithSubtitle = tile.debugTitleFrame
        let iconFrameWithSubtitle = tile.debugIconFrame

        tile.configure(
            item: withoutSubtitle,
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertEqual(tile.debugTitleFrame, titleFrameWithSubtitle)
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
            hud: defaultHUD,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        let unselectedTitleFrame = tile.debugTitleFrame
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
            hud: defaultHUD,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertEqual(tile.debugTitleFrame, unselectedTitleFrame)
        XCTAssertEqual(tile.debugIconFrame, unselectedIconFrame)
    }

    func testThumbnailTileCentersTitleRowWithIcon() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 220, height: 160))
        let snapshot = makeSnapshot(index: 0)
        let item = HUDItem(
            id: "1",
            label: "",
            title: "Ghostty - Terminal",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: false,
            thumbnailState: .placeholder
        )

        tile.configure(
            item: item,
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        tile.layoutSubtreeIfNeeded()

        XCTAssertEqual(tile.debugTitleFrame.midY, tile.debugIconFrame.midY, accuracy: 0.5)
    }

    func testThumbnailTileCentersBadgeAndTitleWithIcon() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 220, height: 160))
        let snapshot = makeSnapshot(index: 0)
        let item = HUDItem(
            id: "1",
            label: "",
            title: "Ghostty - Terminal",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: false,
            windowIndexInApp: 2,
            thumbnailState: .placeholder
        )

        tile.configure(
            item: item,
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        tile.layoutSubtreeIfNeeded()

        XCTAssertEqual(tile.debugTitleFrame.midY, tile.debugIconFrame.midY, accuracy: 0.5)
        XCTAssertEqual(tile.debugBadgeFrame.midY, tile.debugIconFrame.midY, accuracy: 0.5)
    }

    func testRelaxedMetricsProvideMoreBreathingRoom() {
        let metrics = HUDGridMetrics(appearance: .default, hud: defaultHUD)

        XCTAssertGreaterThanOrEqual(metrics.outerPadding, 18)
        XCTAssertGreaterThanOrEqual(metrics.tileWidth, 220)
        XCTAssertGreaterThanOrEqual(metrics.thumbnailHeight, 140)
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
            hud: defaultHUD,
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
            hud: defaultHUD,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let iconOnlySize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            hud: defaultHUD,
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
            hud: defaultHUD,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let iconOnlySize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            hud: defaultHUD,
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        XCTAssertLessThanOrEqual(iconOnlySize.width, thumbnailSize.width)
    }

    func testIconOnlyViewportUsesTighterFootprintForSmallSets() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = sharedMaximumPanelSize()
        let iconOnlySize = contentView.apply(
            model: makeModel(count: 2, selectedIndex: 0),
            appearance: .default,
            hud: defaultHUD,
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        XCTAssertLessThan(iconOnlySize.width, 300)
        XCTAssertLessThan(iconOnlySize.height, 160)
    }

    func testTwoItemIconOnlyHudDoesNotExceedThumbnailFootprint() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = sharedMaximumPanelSize()
        let model = makeModel(count: 2, selectedIndex: 1)

        let thumbnailSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: defaultHUD,
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let iconOnlySize = contentView.apply(
            model: model,
            appearance: .default,
            hud: defaultHUD,
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
            hud: defaultHUD,
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
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )

        XCTAssertFalse(tile.debugTitleIsHidden)
        XCTAssertEqual(tile.debugTitleString, "Example")
    }

    func testIconOnlySelectedTileUsesTranslucentPlate() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 126, height: 154))
        let snapshot = makeSnapshot(index: 0)

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
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )
        tile.layoutSubtreeIfNeeded()

        let backgroundColor = tile.debugBackgroundColor.usingColorSpace(.deviceRGB) ?? .clear
        XCTAssertNotEqual(tile.debugBackgroundFrame, .zero)
        XCTAssertGreaterThan(backgroundColor.alphaComponent, 0.08)
        XCTAssertLessThan(backgroundColor.alphaComponent, 0.16)
        XCTAssertLessThan(abs(backgroundColor.redComponent - backgroundColor.greenComponent), 0.05)
        XCTAssertLessThan(abs(backgroundColor.greenComponent - backgroundColor.blueComponent), 0.05)
        let borderColor = tile.debugBackgroundBorderColor.usingColorSpace(.deviceRGB) ?? .clear
        XCTAssertGreaterThanOrEqual(tile.debugBackgroundBorderWidth, 3)
        XCTAssertGreaterThan(borderColor.alphaComponent, 0.9)
        XCTAssertGreaterThan(borderColor.blueComponent, borderColor.redComponent)
        XCTAssertGreaterThan(borderColor.blueComponent, borderColor.greenComponent)
    }

    func testIconOnlySelectedTileKeepsLabelCloseToSelectionPlate() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 126, height: 154))
        let snapshot = makeSnapshot(index: 0)

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
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )
        tile.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(tile.debugBackgroundFrame.minY - tile.debugTitleFrame.maxY, 3)
    }

    func testIconOnlyTileShowsBadgeForRepeatedAppWindow() {
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
                windowIndexInApp: 2,
                thumbnailState: .unavailable
            ),
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )

        XCTAssertFalse(tile.debugBadgeIsHidden)
        XCTAssertEqual(tile.debugBadgeString, "2")
    }

    func testIconOnlyTileHidesBadgeForSingleWindowApp() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 126, height: 154))
        let snapshot = makeSnapshot(index: 0)

        tile.configure(
            item: HUDItem(
                id: "1",
                label: "Ghostty",
                title: "Terminal",
                pid: snapshot.pid,
                snapshot: snapshot,
                isSelected: true,
                windowIndexInApp: nil,
                thumbnailState: .unavailable
            ),
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )

        XCTAssertTrue(tile.debugBadgeIsHidden)
    }

    func testIconOnlyBadgePlacementIsStableAcrossSelectionState() {
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
                windowIndexInApp: 2,
                thumbnailState: .unavailable
            ),
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )
        tile.layoutSubtreeIfNeeded()
        let unselectedFrame = tile.debugBadgeFrame

        tile.configure(
            item: HUDItem(
                id: "1",
                label: "Ghostty",
                title: "Terminal",
                pid: snapshot.pid,
                snapshot: snapshot,
                isSelected: true,
                windowIndexInApp: 2,
                thumbnailState: .unavailable
            ),
            appearance: .default,
            hud: defaultHUD,
            presentationMode: .iconOnly,
            iconProvider: makeIconProvider()
        )
        tile.layoutSubtreeIfNeeded()

        XCTAssertFalse(tile.debugBadgeIsHidden)
        XCTAssertEqual(tile.debugBadgeString, "2")
        XCTAssertGreaterThan(tile.debugBadgeFrame.minX, 0)
        XCTAssertGreaterThan(tile.debugBadgeFrame.minY, 0)
        XCTAssertNotEqual(tile.debugBadgeFrame, .zero)
        XCTAssertLessThanOrEqual(abs(tile.debugBadgeFrame.midX - unselectedFrame.midX), 16)
        XCTAssertLessThanOrEqual(abs(tile.debugBadgeFrame.midY - unselectedFrame.midY), 16)
    }

    func testThumbnailSizePresetsIncreaseViewportSize() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = CGSize(width: 1440, height: 900)
        let model = makeModel(count: 2, selectedIndex: 0)

        let smallSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: HUDConfig(thumbnails: true, size: .small),
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let mediumSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: HUDConfig(thumbnails: true, size: .medium),
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )
        let largeSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: HUDConfig(thumbnails: true, size: .large),
            maximumSize: maximumSize,
            presentationMode: .thumbnails
        )

        XCTAssertGreaterThan(mediumSize.width, smallSize.width)
        XCTAssertGreaterThan(mediumSize.height, smallSize.height)
        XCTAssertGreaterThan(largeSize.width, mediumSize.width)
        XCTAssertGreaterThan(largeSize.height, mediumSize.height)
    }

    func testIconOnlyViewportIsUnchangedAcrossThumbnailSizePresets() {
        let contentView = HUDPanelContentView(frame: .zero)
        let maximumSize = CGSize(width: 1440, height: 900)
        let model = makeModel(count: 2, selectedIndex: 0)

        let smallSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: HUDConfig(thumbnails: false, size: .small),
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )
        let mediumSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: HUDConfig(thumbnails: false, size: .medium),
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )
        let largeSize = contentView.apply(
            model: model,
            appearance: .default,
            hud: HUDConfig(thumbnails: false, size: .large),
            maximumSize: maximumSize,
            presentationMode: .iconOnly
        )

        XCTAssertEqual(smallSize, mediumSize)
        XCTAssertEqual(mediumSize, largeSize)
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
        HUDGridMetrics(appearance: .default, hud: defaultHUD).maximumPanelSize(
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
