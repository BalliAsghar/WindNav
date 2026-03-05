@testable import TabCore
import Foundation
import XCTest

final class ConfigCoreTests: XCTestCase {
    func testDefaultThumbnailWidthIs220() {
        XCTAssertEqual(TabConfig.default.appearance.thumbnailWidth, 220)
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
        input.activation.overrideSystemCmdTab = false
        input.directional.enabled = false
        input.ordering.pinnedApps = ["com.apple.Safari"]
        input.filters.excludeApps = ["Finder"]
        input.appearance.showThumbnails = false
        input.appearance.thumbnailWidth = 220
        input.performance.logColor = .never

        try loader.save(input)
        let reparsed = try loader.loadOrCreate()

        XCTAssertEqual(reparsed, input)
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
}
