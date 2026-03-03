@testable import TabCore
import Foundation
import XCTest

final class ConfigLoaderTests: XCTestCase {
    func testLoadOrCreateWritesDefaultConfig() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "tabpp-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let configURL = temp.appending(path: "config.toml", directoryHint: .notDirectory)
        let loader = ConfigLoader(configURL: configURL)

        let config = try loader.loadOrCreate()

        XCTAssertEqual(config, .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testParseInvalidOrderingModeThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [ordering]
                mode = "spatial"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }
            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "ordering.mode")
                    XCTAssertEqual(expected, "fixed|most-recent|pinned")
                    XCTAssertEqual(actual, "spatial")
                default:
                    XCTFail("Expected invalidValue, got \(configError)")
            }
        }
    }

    func testParseOutOfRangeIconSizeThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [appearance]
                icon-size = 100
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }
            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "appearance.icon-size")
                    XCTAssertEqual(expected, "integer in range 14...64")
                    XCTAssertEqual(actual, "100")
                default:
                    XCTFail("Expected invalidValue, got \(configError)")
            }
        }
    }

    func testUnknownKeysAreIgnored() throws {
        let cfg = try ConfigLoader.parse(
            """
            [activation]
            trigger = "cmd-tab"
            unknown-activation = "value"

            [performance]
            log-level = "debug"
            log-color = "always"
            noisy = true
            """
        )

        XCTAssertEqual(cfg.activation.trigger, "cmd-tab")
        XCTAssertEqual(cfg.performance.logLevel, .debug)
        XCTAssertEqual(cfg.performance.logColor, .always)
    }

    func testParseDefaultToml() throws {
        let cfg = try ConfigLoader.parse(TabConfig.defaultToml)

        XCTAssertEqual(cfg.activation.trigger, "cmd-tab")
        XCTAssertEqual(cfg.activation.reverseTrigger, "cmd-shift-tab")
        XCTAssertTrue(cfg.activation.overrideSystemCmdTab)

        XCTAssertTrue(cfg.visibility.showMinimized)
        XCTAssertTrue(cfg.visibility.showHidden)
        XCTAssertTrue(cfg.visibility.showFullscreen)
        XCTAssertEqual(cfg.visibility.showEmptyApps, .showAtEnd)

        XCTAssertEqual(cfg.ordering.mode, .mostRecent)
        XCTAssertEqual(cfg.appearance.theme, .system)
        XCTAssertEqual(cfg.appearance.iconSize, 22)
        XCTAssertEqual(cfg.performance.logColor, .auto)
    }

    func testParseCustomLogColor() throws {
        let cfg = try ConfigLoader.parse(
            """
            [performance]
            log-color = "always"
            """
        )

        XCTAssertEqual(cfg.performance.logColor, .always)
    }

    func testParseShowEmptyAppsStringHide() throws {
        let cfg = try ConfigLoader.parse(
            """
            [visibility]
            show-empty-apps = "hide"
            """
        )

        XCTAssertEqual(cfg.visibility.showEmptyApps, .hide)
    }

    func testParseShowEmptyAppsStringShow() throws {
        let cfg = try ConfigLoader.parse(
            """
            [visibility]
            show-empty-apps = "show"
            """
        )

        XCTAssertEqual(cfg.visibility.showEmptyApps, .show)
    }

    func testParseShowEmptyAppsLegacyTrueMapsToShow() throws {
        let cfg = try ConfigLoader.parse(
            """
            [visibility]
            show-empty-apps = true
            """
        )

        XCTAssertEqual(cfg.visibility.showEmptyApps, .show)
    }

    func testParseShowEmptyAppsLegacyFalseMapsToHide() throws {
        let cfg = try ConfigLoader.parse(
            """
            [visibility]
            show-empty-apps = false
            """
        )

        XCTAssertEqual(cfg.visibility.showEmptyApps, .hide)
    }

    func testParseInvalidShowEmptyAppsThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [visibility]
                show-empty-apps = "middle"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }
            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "visibility.show-empty-apps")
                    XCTAssertEqual(expected, "hide|show|show-at-end")
                    XCTAssertEqual(actual, "middle")
                default:
                    XCTFail("Expected invalidValue, got \(configError)")
            }
        }
    }

    func testParseInvalidLogColorThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [performance]
                log-color = "rainbow"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }
            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "performance.log-color")
                    XCTAssertEqual(expected, "auto|always|never")
                    XCTAssertEqual(actual, "rainbow")
                default:
                    XCTFail("Expected invalidValue, got \(configError)")
            }
        }
    }
}
