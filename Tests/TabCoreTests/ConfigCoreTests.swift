@testable import TabCore
import Foundation
import XCTest

final class ConfigCoreTests: XCTestCase {
    func testDefaultThumbnailWidthIs220() {
        XCTAssertEqual(TabConfig.default.appearance.thumbnailWidth, 220)
    }

    func testDefaultDirectionalThumbnailsDisabled() {
        XCTAssertFalse(TabConfig.default.directional.showThumbnails)
    }

    func testDefaultLaunchAtLoginDisabled() {
        XCTAssertFalse(TabConfig.default.onboarding.launchAtLoginEnabled)
    }

    func testDefaultConfigPathUsesWindNavDirectory() {
        let path = ConfigLoader.defaultConfigURL().path
        XCTAssertTrue(path.hasSuffix("/.config/windnav/config.toml"))
    }

    func testLoadOrCreateWritesDefaultFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = dir.appending(path: "config.toml", directoryHint: .notDirectory)
        let loader = ConfigLoader(configURL: url)

        let loaded = try loader.loadOrCreate()

        XCTAssertEqual(loaded.activation.trigger, TabConfig.default.activation.trigger)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSaveAndReloadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = dir.appending(path: "config.toml", directoryHint: .notDirectory)
        let loader = ConfigLoader(configURL: url)

        var input = TabConfig.default
        input.directional.enabled = false
        input.directional.showThumbnails = false
        input.ordering.pinnedApps = ["com.apple.Safari"]
        input.filters.excludeApps = ["Finder"]
        input.appearance.showThumbnails = false
        input.appearance.thumbnailWidth = 220
        input.performance.logColor = .never
        input.onboarding.launchAtLoginEnabled = true

        try loader.save(input)
        let reparsed = try loader.loadOrCreate()

        XCTAssertEqual(reparsed, input)
    }

    func testSerializeOmitsDeprecatedOverrideSystemCmdTabKey() {
        let text = ConfigLoader.serialize(.default)
        XCTAssertFalse(text.contains("override-system-cmd-tab"))
    }

    func testSerializeIncludesDirectionalThumbnailKey() {
        let text = ConfigLoader.serialize(.default)
        XCTAssertTrue(text.contains("show-thumbnails = false"))
        XCTAssertTrue(text.contains("[directional]"))
    }

    func testMissingLaunchAtLoginKeyDefaultsToFalse() throws {
        let text = """
        [onboarding]
        permission-explainer-shown = true
        """

        let parsed = try ConfigLoader.parse(text)
        XCTAssertFalse(parsed.onboarding.launchAtLoginEnabled)
    }

    func testDeprecatedOverrideSystemCmdTabKeyIsAcceptedAndIgnored() throws {
        let text = """
        [activation]
        override-system-cmd-tab = false
        """

        let parsed = try ConfigLoader.parse(text)
        XCTAssertEqual(parsed.activation.trigger, TabConfig.default.activation.trigger)
        XCTAssertEqual(parsed.activation.reverseTrigger, TabConfig.default.activation.reverseTrigger)
    }

    func testParseOutOfRangeIconSizeThrows() {
        let text = """
        [appearance]
        icon-size = 999
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.icon-size")
        }
    }

    func testParseOutOfRangeThumbnailWidthThrows() {
        let text = """
        [appearance]
        thumbnail-width = 8
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.thumbnail-width")
        }
    }

    func testDirectionalThumbnailFlagDefaultsToFalseWhenMissing() throws {
        let text = """
        [directional]
        enabled = true
        """

        let parsed = try ConfigLoader.parse(text)
        XCTAssertFalse(parsed.directional.showThumbnails)
    }
}
