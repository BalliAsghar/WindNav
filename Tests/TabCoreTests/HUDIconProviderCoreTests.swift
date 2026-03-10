@testable import TabCore
import AppKit
import XCTest

@MainActor
final class HUDIconProviderCoreTests: XCTestCase {
    func testProviderCachesRasterizedIconsByIdentitySizeAndScale() {
        let source = CountingHUDIconSource()
        let provider = HUDIconProvider(source: source)
        let snapshot = makeSnapshot()

        let first = provider.icon(for: snapshot, pointSize: 96, scale: 2)
        let second = provider.icon(for: snapshot, pointSize: 96, scale: 2)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(source.requests, 1)
        XCTAssertEqual(provider.cachedIconCount(), 1)
    }

    func testProviderRerasterizesWhenRequestedSizeChanges() {
        let source = CountingHUDIconSource()
        let provider = HUDIconProvider(source: source)
        let snapshot = makeSnapshot()

        _ = provider.icon(for: snapshot, pointSize: 96, scale: 2)
        _ = provider.icon(for: snapshot, pointSize: 110, scale: 2)

        XCTAssertEqual(source.requests, 2)
        XCTAssertEqual(provider.cachedIconCount(), 2)
    }

    func testProviderRasterizesToRequestedPixelDimensions() {
        let provider = HUDIconProvider(source: CountingHUDIconSource())
        let snapshot = makeSnapshot()

        let icon = provider.icon(for: snapshot, pointSize: 112, scale: 2)

        XCTAssertEqual(icon?.width, 224)
        XCTAssertEqual(icon?.height, 224)
    }

    func testProviderCachesDistinctScaleBucketsSeparately() {
        let source = CountingHUDIconSource()
        let provider = HUDIconProvider(source: source)
        let snapshot = makeSnapshot()

        _ = provider.icon(for: snapshot, pointSize: 112, scale: 2)
        _ = provider.icon(for: snapshot, pointSize: 112, scale: 3)

        XCTAssertEqual(source.requests, 2)
        XCTAssertEqual(provider.cachedIconCount(), 2)
    }

    func testProviderReturnsNilWhenSourceHasNoIcon() {
        let provider = HUDIconProvider(source: EmptyHUDIconSource())

        XCTAssertNil(provider.icon(for: makeSnapshot(), pointSize: 96, scale: 2))
    }

    private func makeSnapshot() -> WindowSnapshot {
        WindowSnapshot(
            windowId: 1,
            pid: 42,
            bundleId: "com.example.icon",
            appName: "Example",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "Example",
            revision: 1
        )
    }
}

@MainActor
private final class CountingHUDIconSource: HUDIconSourcing {
    private(set) var requests = 0

    func image(for snapshot: WindowSnapshot) -> NSImage? {
        requests += 1
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 512, height: 512), xRadius: 96, yRadius: 96).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private struct EmptyHUDIconSource: HUDIconSourcing {
    func image(for snapshot: WindowSnapshot) -> NSImage? {
        nil
    }
}
