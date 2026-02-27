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
        XCTAssertTrue(rendered.contains("# Allowed: true|false"))
        XCTAssertTrue(rendered.contains("# Default: \"middle-center\""))
    }

    func testDefaultHUDValuesAreEnabledWithIconsInMiddle() {
        let hud = WindNavConfig.default.hud
        XCTAssertTrue(hud.enabled)
        XCTAssertTrue(hud.showIcons)
        XCTAssertEqual(hud.position, .middleCenter)
    }
}
