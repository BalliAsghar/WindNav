@testable import TabCore
import Foundation
import XCTest

final class ConfigCoreTests: XCTestCase {
    func testDefaultLaunchAtLoginDisabled() {
        XCTAssertFalse(TabConfig.default.onboarding.launchAtLoginEnabled)
    }

    func testDefaultHUDThumbnailsEnabled() {
        XCTAssertTrue(TabConfig.default.hud.thumbnails)
        XCTAssertEqual(TabConfig.default.hud.size, .small)
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
        input.ordering.pinnedApps = ["com.apple.Safari"]
        input.filters.excludeApps = ["Finder"]
        input.performance.logColor = .never
        input.onboarding.launchAtLoginEnabled = true
        input.hud.thumbnails = false
        input.hud.size = .large

        try loader.save(input)
        let reparsed = try loader.loadOrCreate()

        XCTAssertEqual(reparsed, input)
    }

    func testSerializeOmitsDeprecatedOverrideSystemCmdTabKey() {
        let text = ConfigLoader.serialize(.default)
        XCTAssertFalse(text.contains("override-system-cmd-tab"))
    }

    func testSerializeOmitsRemovedThumbnailKeys() {
        let text = ConfigLoader.serialize(.default)
        XCTAssertFalse(text.contains("show-thumbnails"))
        XCTAssertFalse(text.contains("thumbnail-width"))
        XCTAssertFalse(text.contains("icon-size"))
        XCTAssertFalse(text.contains("item-padding"))
        XCTAssertFalse(text.contains("item-spacing"))
    }

    func testSerializeIncludesHUDSection() {
        let text = ConfigLoader.serialize(.default)

        XCTAssertTrue(text.contains("[hud]"))
        XCTAssertTrue(text.contains("thumbnails = true"))
        XCTAssertTrue(text.contains("size = \"small\""))
    }

    func testMissingLaunchAtLoginKeyDefaultsToFalse() throws {
        let text = """
        [onboarding]
        permission-explainer-shown = true
        """

        let parsed = try ConfigLoader.parse(text)
        XCTAssertFalse(parsed.onboarding.launchAtLoginEnabled)
    }

    func testRemovedOverrideSystemCmdTabKeyThrows() {
        let text = """
        [activation]
        override-system-cmd-tab = false
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "activation.override-system-cmd-tab")
        }
    }

    func testRemovedReverseTriggerKeyThrows() {
        let text = """
        [activation]
        reverse-trigger = "cmd-shift-tab"
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "activation.reverse-trigger")
        }
    }

    func testRemovedAppearanceIconSizeKeyThrowsMigrationError() {
        let text = """
        [appearance]
        icon-size = 999
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, let expected, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.icon-size")
            XCTAssertEqual(expected, "key removed; use hud.size instead")
        }
    }

    func testRemovedAppearanceItemPaddingKeyThrowsMigrationError() {
        let text = """
        [appearance]
        item-padding = 12
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, let expected, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.item-padding")
            XCTAssertEqual(expected, "key removed; use hud.size instead")
        }
    }

    func testRemovedAppearanceItemSpacingKeyThrowsMigrationError() {
        let text = """
        [appearance]
        item-spacing = 12
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, let expected, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.item-spacing")
            XCTAssertEqual(expected, "key removed; use hud.size instead")
        }
    }

    func testRemovedAppearanceThumbnailKeyThrows() {
        let text = """
        [appearance]
        show-thumbnails = true
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.show-thumbnails")
        }
    }

    func testRemovedAppearanceThumbnailWidthKeyThrows() {
        let text = """
        [appearance]
        thumbnail-width = 220
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "appearance.thumbnail-width")
        }
    }

    func testRemovedDirectionalThumbnailKeyThrows() {
        let text = """
        [directional]
        show-thumbnails = true
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "directional.show-thumbnails")
        }
    }

    func testInvalidHUDThumbnailsValueThrows() {
        let text = """
        [hud]
        thumbnails = "yes"
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "hud.thumbnails")
        }
    }

    func testInvalidHUDSizeValueThrows() {
        let text = """
        [hud]
        size = "huge"
        """

        XCTAssertThrowsError(try ConfigLoader.parse(text)) { error in
            guard case ConfigError.invalidValue(let key, _, _) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertEqual(key, "hud.size")
        }
    }
}
