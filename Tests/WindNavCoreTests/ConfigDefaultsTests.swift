@testable import WindNavCore
import XCTest

final class ConfigDefaultsTests: XCTestCase {
    func testRenderedDefaultsTomlParsesToDefaultConfig() throws {
        let rendered = WindNavDefaultsCatalog.renderedToml
        let parsed = try ConfigLoader.parse(rendered)
        XCTAssertEqual(parsed, WindNavConfig.default)
    }

    func testRenderedDefaultsTomlIncludesDynamicMetadataComments() {
        let rendered = WindNavDefaultsCatalog.renderedToml
        XCTAssertTrue(rendered.contains("# Whether to show the cycle HUD while navigating."))
        XCTAssertTrue(rendered.contains("# Pixel size for app icons shown in the HUD."))
        XCTAssertTrue(rendered.contains("# Whether minimized windows should be included in navigation."))
        XCTAssertTrue(rendered.contains("# Whether app windows from hidden apps should be included in navigation."))
        XCTAssertTrue(rendered.contains("# Allowed: true|false"))
        XCTAssertTrue(rendered.contains("# Allowed: positive integer pixels"))
        XCTAssertTrue(rendered.contains("# Default: \"middle-center\""))
        XCTAssertTrue(rendered.contains("icon-size = 22"))
        XCTAssertTrue(rendered.contains("# Default: true"))
    }

    func testDefaultHUDValuesAreEnabledWithIconsInMiddle() {
        let hud = WindNavConfig.default.hud
        XCTAssertTrue(hud.enabled)
        XCTAssertTrue(hud.showIcons)
        XCTAssertEqual(hud.iconSize, 22)
        XCTAssertEqual(hud.position, .middleCenter)
    }

    func testDefaultNavigationIncludesMinimizedAndHiddenApps() {
        let navigation = WindNavConfig.default.navigation
        XCTAssertEqual(navigation.mode, .standard)
        XCTAssertTrue(navigation.includeMinimized)
        XCTAssertTrue(navigation.includeHiddenApps)
    }
}
