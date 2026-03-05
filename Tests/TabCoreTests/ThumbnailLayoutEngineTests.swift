@testable import TabCore
import CoreGraphics
import XCTest

final class ThumbnailLayoutEngineTests: XCTestCase {
    func testPortraitWindowsUseNarrowerTilesThanLandscape() {
        let layout = ThumbnailLayoutEngine.makeLayout(
            items: [
                ThumbnailLayoutEngine.ItemInput(thumbnailPixelSize: nil, aspectRatioHint: 0.55),
                ThumbnailLayoutEngine.ItemInput(thumbnailPixelSize: nil, aspectRatioHint: 1.6),
            ],
            requestedThumbnailWidth: 220,
            itemSpacing: 8,
            itemPadding: 8,
            iconSize: 22,
            maxPanelWidth: 1600
        )

        XCTAssertLessThan(layout.itemMetrics[0].thumbnailWidth, layout.itemMetrics[1].thumbnailWidth)
    }

    func testPlaceholderWidthMatchesImageWidthWhenRatiosMatch() {
        let hintLayout = ThumbnailLayoutEngine.makeLayout(
            items: [
                ThumbnailLayoutEngine.ItemInput(thumbnailPixelSize: nil, aspectRatioHint: 0.55),
            ],
            requestedThumbnailWidth: 220,
            itemSpacing: 8,
            itemPadding: 8,
            iconSize: 22,
            maxPanelWidth: 1000
        )
        let imageLayout = ThumbnailLayoutEngine.makeLayout(
            items: [
                ThumbnailLayoutEngine.ItemInput(thumbnailPixelSize: CGSize(width: 110, height: 200), aspectRatioHint: nil),
            ],
            requestedThumbnailWidth: 220,
            itemSpacing: 8,
            itemPadding: 8,
            iconSize: 22,
            maxPanelWidth: 1000
        )

        XCTAssertEqual(hintLayout.itemMetrics[0].thumbnailWidth, imageLayout.itemMetrics[0].thumbnailWidth, accuracy: 0.001)
    }

    func testLayoutRespectsPanelWidthWhenFitIsPossible() {
        let items = (0..<6).map { _ in
            ThumbnailLayoutEngine.ItemInput(thumbnailPixelSize: nil, aspectRatioHint: 1.6)
        }
        let maxPanelWidth: CGFloat = 900
        let layout = ThumbnailLayoutEngine.makeLayout(
            items: items,
            requestedThumbnailWidth: 220,
            itemSpacing: 8,
            itemPadding: 8,
            iconSize: 22,
            maxPanelWidth: maxPanelWidth
        )

        XCTAssertLessThanOrEqual(layout.contentSize.width, maxPanelWidth)
        XCTAssertGreaterThanOrEqual(layout.baseThumbnailWidth, ThumbnailLayoutEngine.minimumThumbnailWidth)
    }

    func testManyWindowsStopsAtMinimumThumbnailWidth() {
        let items = (0..<30).map { _ in
            ThumbnailLayoutEngine.ItemInput(thumbnailPixelSize: nil, aspectRatioHint: 1.6)
        }
        let layout = ThumbnailLayoutEngine.makeLayout(
            items: items,
            requestedThumbnailWidth: 220,
            itemSpacing: 8,
            itemPadding: 8,
            iconSize: 22,
            maxPanelWidth: 900
        )

        XCTAssertEqual(layout.baseThumbnailWidth, ThumbnailLayoutEngine.minimumThumbnailWidth, accuracy: 0.001)
        XCTAssertTrue(layout.itemMetrics.allSatisfy { $0.thumbnailWidth >= ThumbnailLayoutEngine.minimumThumbnailWidth })
    }
}
