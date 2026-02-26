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
}
