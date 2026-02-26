@testable import WindNavCore
import XCTest

final class ConfigTests: XCTestCase {
    func testParseValidConfig() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"

            [navigation]
            scope = "current-monitor"
            policy = "mru-cycle"
            no-candidate = "noop"
            filtering = "conservative"
            cycle-timeout-ms = 900

            [logging]
            level = "info"
            color = "auto"

            [startup]
            launch-on-login = true
            """
        )

        XCTAssertEqual(cfg.navigation.scope, .currentMonitor)
        XCTAssertEqual(cfg.navigation.policy, .mruCycle)
        XCTAssertEqual(cfg.navigation.noCandidate, .noop)
        XCTAssertEqual(cfg.navigation.filtering, .conservative)
        XCTAssertEqual(cfg.navigation.cycleTimeoutMs, 900)
        XCTAssertEqual(cfg.hotkeys.focusLeft, "cmd-left")
        XCTAssertEqual(cfg.logging.level, .info)
        XCTAssertEqual(cfg.logging.color, .auto)
        XCTAssertEqual(cfg.startup.launchOnLogin, true)
    }

    func testParseNaturalPolicyAliasMapsToMruCycle() throws {
        let cfg = try ConfigLoader.parse(
            """
            [navigation]
            policy = "natural"
            """
        )

        XCTAssertEqual(cfg.navigation.policy, .mruCycle)
    }

    func testParseDeprecatedUpDownHotkeysIsTolerated() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"
            focus-up = "cmd-up"
            focus-down = "cmd-down"
            """
        )

        XCTAssertEqual(cfg.hotkeys.focusLeft, "cmd-left")
        XCTAssertEqual(cfg.hotkeys.focusRight, "cmd-right")
    }

    func testMissingStartupSectionDefaultsToFalse() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"
            """
        )

        XCTAssertFalse(cfg.startup.launchOnLogin)
    }

    func testParseInvalidNavigationScopeThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                scope = "all-monitors"
                """
            )
        )
    }

    func testParseInvalidNavigationPolicyThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                policy = "spatial"
                """
            )
        )
    }

    func testParseInvalidCycleTimeoutThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                cycle-timeout-ms = 0
                """
            )
        )
    }

    func testParseInvalidLoggingLevelThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [logging]
                level = "debug"
                """
            )
        )
    }

    func testParseInvalidLoggingColorThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [logging]
                color = "rainbow"
                """
            )
        )
    }

    func testParseInvalidStartupLaunchOnLoginTypeThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [startup]
                launch-on-login = "yes"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }

            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "startup.launch-on-login")
                    XCTAssertEqual(expected, "true|false")
                    XCTAssertEqual(actual, "\"yes\"")
                default:
                    XCTFail("Expected invalidValue for startup.launch-on-login, got \(configError)")
            }
        }
    }
}
