@testable import TabCore
import XCTest

@MainActor
final class HUDThumbnailToggleCoreTests: XCTestCase {
    func testHUDModelFactoryStartsIconOnlyWhenThumbnailsDisabled() {
        let snapshot = makeSnapshot(canCaptureThumbnail: true)

        let model = HUDModelFactory.makeModel(
            windows: [snapshot],
            selectedIndex: 0,
            appearance: .default,
            hud: HUDConfig(thumbnails: false)
        )

        XCTAssertEqual(model.items.map(\.thumbnailState), [.unavailable])
    }

    func testHUDModelFactoryStartsWithPlaceholderWhenThumbnailsEnabled() {
        let snapshot = makeSnapshot(canCaptureThumbnail: true)

        let model = HUDModelFactory.makeModel(
            windows: [snapshot],
            selectedIndex: 0,
            appearance: .default,
            hud: HUDConfig(thumbnails: true)
        )

        XCTAssertEqual(model.items.map(\.thumbnailState), [.placeholder])
    }

    func testShouldCaptureThumbnailsRequiresFeatureAndPermission() {
        XCTAssertFalse(
            MinimalHUDController.shouldCaptureThumbnails(
                hud: HUDConfig(thumbnails: false),
                screenRecordingGranted: true
            )
        )
        XCTAssertFalse(
            MinimalHUDController.shouldCaptureThumbnails(
                hud: HUDConfig(thumbnails: true),
                screenRecordingGranted: false
            )
        )
        XCTAssertTrue(
            MinimalHUDController.shouldCaptureThumbnails(
                hud: HUDConfig(thumbnails: true),
                screenRecordingGranted: true
            )
        )
    }

    private func makeSnapshot(canCaptureThumbnail: Bool) -> WindowSnapshot {
        WindowSnapshot(
            windowId: 1,
            pid: 100,
            bundleId: "com.example.test",
            appName: "Example",
            frame: CGRect(x: 0, y: 0, width: 1200, height: 700),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "Example",
            canCaptureThumbnail: canCaptureThumbnail,
            revision: 1
        )
    }
}
