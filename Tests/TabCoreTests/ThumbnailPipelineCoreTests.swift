@testable import TabCore
import AppKit
import CoreGraphics
import QuartzCore
import XCTest

@MainActor
final class ThumbnailPipelineCoreTests: XCTestCase {
    func testCapturePixelSizePreservesSplitWindowAspectRatioWithinBounds() {
        let captureSize = ThumbnailSizing.capturePixelSize(
            logicalWindowSize: CGSize(width: 1391, height: 762),
            targetSize: CGSize(width: 136, height: 86),
            scaleFactor: 2
        )

        XCTAssertLessThanOrEqual(captureSize.width, 272)
        XCTAssertLessThanOrEqual(captureSize.height, 172)
        XCTAssertEqual(
            captureSize.width / captureSize.height,
            CGFloat(1391) / CGFloat(762),
            accuracy: 0.03
        )
    }

    func testAspectFitRectCentersMismatchedSource() {
        let rect = ThumbnailSizing.aspectFitRect(
            sourceSize: CGSize(width: 1600, height: 900),
            boundingSize: CGSize(width: 300, height: 300)
        )

        XCTAssertEqual(rect.width, 300, accuracy: 0.5)
        XCTAssertEqual(rect.height, 169, accuracy: 1)
        XCTAssertEqual(rect.minY, 66, accuracy: 1)
    }

    func testThumbnailSurfaceApplyUsesResizeInsteadOfFill() {
        let surface = ThumbnailSurface(cgImage: makeTestImage(width: 4, height: 2))
        let layer = CALayer()

        surface.apply(to: layer)

        XCTAssertEqual(layer.contentsGravity, .resize)
        XCTAssertNotNil(layer.contents)
    }

    func testTileKeepsThumbnailWhenSelectionChangesForSameWindowRevision() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 200, height: 140))
        let snapshot = makeSnapshot(windowId: 1, revision: 10)
        let surface = ThumbnailSurface(cgImage: makeTestImage(width: 16, height: 9))

        tile.configure(
            item: makeItem(snapshot: snapshot, isSelected: false),
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        tile.applyThumbnail(.freshStill, surface: surface)
        XCTAssertTrue(tile.debugPreviewHasContents)

        tile.configure(
            item: makeItem(snapshot: snapshot, isSelected: true),
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertTrue(tile.debugPreviewHasContents)
    }

    func testTileClearsThumbnailWhenReusedForDifferentRevision() {
        let tile = HUDThumbnailTileView(frame: CGRect(x: 0, y: 0, width: 200, height: 140))
        let surface = ThumbnailSurface(cgImage: makeTestImage(width: 16, height: 9))

        tile.configure(
            item: makeItem(snapshot: makeSnapshot(windowId: 1, revision: 10), isSelected: false),
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )
        tile.applyThumbnail(.freshStill, surface: surface)
        XCTAssertTrue(tile.debugPreviewHasContents)

        tile.configure(
            item: makeItem(snapshot: makeSnapshot(windowId: 1, revision: 11), isSelected: false),
            appearance: .default,
            presentationMode: .thumbnails,
            iconProvider: makeIconProvider()
        )

        XCTAssertFalse(tile.debugPreviewHasContents)
    }

    private func makeSnapshot(windowId: UInt32, revision: UInt64) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: 900,
            bundleId: "com.example.test",
            appName: "Test",
            frame: CGRect(x: 0, y: 0, width: 1200, height: 700),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "Window",
            revision: revision
        )
    }

    private func makeItem(snapshot: WindowSnapshot, isSelected: Bool) -> HUDItem {
        HUDItem(
            id: "\(snapshot.windowId)",
            label: "Test",
            title: snapshot.title ?? "Window",
            pid: snapshot.pid,
            snapshot: snapshot,
            isSelected: isSelected,
            thumbnailState: .placeholder
        )
    }

    private func makeTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeIconProvider() -> HUDIconProvider {
        HUDIconProvider(source: ThumbnailTestIconSource())
    }
}

@MainActor
private struct ThumbnailTestIconSource: HUDIconSourcing {
    func image(for snapshot: WindowSnapshot) -> NSImage? {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 64, height: 64), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()
        return image
    }
}
