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

            [hud]
            enabled = true
            show-window-count = false
            position = "top-center"
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
        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertFalse(cfg.hud.showWindowCount)
        XCTAssertEqual(cfg.hud.position, .topCenter)
    }

    func testParseFixedAppRingAndHUDConfig() throws {
        let cfg = try ConfigLoader.parse(
            """
            [navigation]
            policy = "fixed-app-ring"

            [navigation.fixed-app-ring]
            pinned-apps = ["com.google.Chrome", "com.apple.Terminal"]
            unpinned-apps = "append"
            in-app-window = "last-focused-on-monitor"
            grouping = "one-stop-per-app"

            [hud]
            enabled = true
            show-window-count = true
            position = "top-center"
            """
        )

        XCTAssertEqual(cfg.navigation.policy, .fixedAppRing)
        XCTAssertEqual(cfg.navigation.fixedAppRing.pinnedApps, ["com.google.Chrome", "com.apple.Terminal"])
        XCTAssertEqual(cfg.navigation.fixedAppRing.unpinnedApps, .append)
        XCTAssertEqual(cfg.navigation.fixedAppRing.inAppWindow, .lastFocusedOnMonitor)
        XCTAssertEqual(cfg.navigation.fixedAppRing.grouping, .oneStopPerApp)
        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertTrue(cfg.hud.showWindowCount)
        XCTAssertEqual(cfg.hud.position, .topCenter)
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

    func testParseInvalidFixedAppRingUnpinnedAppsThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.fixed-app-ring]
                unpinned-apps = "random"
                """
            )
        )
    }

    func testParseInvalidFixedAppRingInAppWindowThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.fixed-app-ring]
                in-app-window = "mru"
                """
            )
        )
    }

    func testParseInvalidFixedAppRingGroupingThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.fixed-app-ring]
                grouping = "per-window"
                """
            )
        )
    }

    func testParseInvalidHUDPositionThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [hud]
                position = "bottom-left"
                """
            )
        )
    }

    func testParseNonArrayPinnedAppsThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.fixed-app-ring]
                pinned-apps = "com.apple.Terminal"
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
