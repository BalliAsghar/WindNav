@testable import TabCore
import XCTest

final class HUDMetadataCoreTests: XCTestCase {
    func testMetadataFormatterUsesCombinedAppNameAndWindowTitle() {
        let lines = HUDMetadataFormatter.lines(for: makeSnapshot(title: "YouTube", appName: "Google Chrome"))

        XCTAssertEqual(lines.primary, "Google Chrome - YouTube")
        XCTAssertEqual(lines.secondary, "")
    }

    func testMetadataFormatterFallsBackToAppNameWhenWindowTitleMissing() {
        let lines = HUDMetadataFormatter.lines(for: makeSnapshot(title: nil, appName: "Codex"))

        XCTAssertEqual(lines.primary, "Codex")
        XCTAssertEqual(lines.secondary, "")
    }

    func testMetadataFormatterTreatsDuplicateTitleAsSingleVisibleValue() {
        let lines = HUDMetadataFormatter.lines(for: makeSnapshot(title: "Ghostty", appName: "Ghostty"))

        XCTAssertEqual(lines.primary, "Ghostty")
        XCTAssertEqual(lines.secondary, "")
    }

    func testMetadataFormatterTreatsWhitespaceTitleAsMissing() {
        let lines = HUDMetadataFormatter.lines(for: makeSnapshot(title: "   ", appName: "Ghostty"))

        XCTAssertEqual(lines.primary, "Ghostty")
        XCTAssertEqual(lines.secondary, "")
    }

    func testHUDModelFactoryBuildsNormalizedMetadataLines() {
        let windows = [
            makeSnapshot(windowId: 1, title: "Docs", appName: "Codex"),
            makeSnapshot(windowId: 2, title: "Codex", appName: "Codex"),
            makeSnapshot(windowId: 3, title: nil, appName: "Ghostty")
        ]

        let model = HUDModelFactory.makeModel(
            windows: windows,
            selectedIndex: 0,
            appearance: .default,
            hud: .default
        )

        XCTAssertEqual(model.items.map(\.title), ["Codex - Docs", "Codex", "Ghostty"])
        XCTAssertEqual(model.items.map(\.label), ["", "", ""])
    }

    private func makeSnapshot(
        windowId: UInt32 = 1,
        title: String?,
        appName: String?
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: 101,
            bundleId: "com.example.test",
            appName: appName,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 700),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: title
        )
    }
}
