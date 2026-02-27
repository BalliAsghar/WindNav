@testable import WindNavCore
import Foundation
import XCTest

final class ConfigTests: XCTestCase {
    private final class SinkLines: @unchecked Sendable {
        private var lines: [String] = []
        private let lock = NSLock()

        func append(_ line: String) {
            lock.lock()
            lines.append(line)
            lock.unlock()
        }

        func contains(_ needle: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return lines.contains { $0.contains(needle) }
        }
    }

    func testParseValidConfig() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"

            [navigation]
            mode = "standard"
            cycle-timeout-ms = 900
            include-minimized = false
            include-hidden-apps = true

            [logging]
            level = "info"
            color = "auto"

            [startup]
            launch-on-login = true

            [hud]
            enabled = true
            show-icons = true
            position = "top-center"
            """
        )

        XCTAssertEqual(cfg.navigation.mode, .standard)
        XCTAssertEqual(cfg.navigation.cycleTimeoutMs, 900)
        XCTAssertFalse(cfg.navigation.includeMinimized)
        XCTAssertTrue(cfg.navigation.includeHiddenApps)
        XCTAssertEqual(cfg.hotkeys.focusLeft, "cmd-left")
        XCTAssertEqual(cfg.hotkeys.focusUp, "cmd-up")
        XCTAssertEqual(cfg.hotkeys.focusDown, "cmd-down")
        XCTAssertEqual(cfg.logging.level, .info)
        XCTAssertEqual(cfg.logging.color, .auto)
        XCTAssertEqual(cfg.startup.launchOnLogin, true)
        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertTrue(cfg.hud.showIcons)
        XCTAssertEqual(cfg.hud.position, .topCenter)
    }

    func testParseStandardNavigationAndHUDConfig() throws {
        let cfg = try ConfigLoader.parse(
            """
            [navigation]
            mode = "standard"
            include-minimized = true
            include-hidden-apps = false

            [navigation.standard]
            pinned-apps = ["com.google.Chrome", "com.apple.Terminal"]
            unpinned-apps = "append"
            in-app-window = "last-focused-on-monitor"
            grouping = "one-stop-per-app"

            [hud]
            enabled = true
            show-icons = false
            position = "top-center"
            """
        )

        XCTAssertEqual(cfg.navigation.mode, .standard)
        XCTAssertTrue(cfg.navigation.includeMinimized)
        XCTAssertFalse(cfg.navigation.includeHiddenApps)
        XCTAssertEqual(cfg.navigation.fixedAppRing.pinnedApps, ["com.google.Chrome", "com.apple.Terminal"])
        XCTAssertEqual(cfg.navigation.fixedAppRing.unpinnedApps, .append)
        XCTAssertEqual(cfg.navigation.fixedAppRing.inAppWindow, .lastFocusedOnMonitor)
        XCTAssertEqual(cfg.navigation.fixedAppRing.grouping, .oneStopPerApp)
        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertFalse(cfg.hud.showIcons)
        XCTAssertEqual(cfg.hud.position, .topCenter)
    }

    func testLegacyNavigationPolicyKeyThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                policy = "fixed-app-ring"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }

            switch configError {
                case let .invalidValue(key, expected, _):
                    XCTAssertEqual(key, "navigation.policy")
                    XCTAssertEqual(expected, "removed; use navigation.mode = \"standard\"")
                default:
                    XCTFail("Expected invalidValue for navigation.policy, got \(configError)")
            }
        }
    }

    func testLegacyNavigationFixedAppRingTableThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.fixed-app-ring]
                pinned-apps = ["com.apple.Terminal"]
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }

            switch configError {
                case let .invalidValue(key, expected, _):
                    XCTAssertEqual(key, "navigation.fixed-app-ring")
                    XCTAssertEqual(expected, "removed; use [navigation.standard]")
                default:
                    XCTFail("Expected invalidValue for navigation.fixed-app-ring, got \(configError)")
            }
        }
    }

    func testLegacyNavigationModeValueFixedAppRingThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                mode = "fixed-app-ring"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }

            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "navigation.mode")
                    XCTAssertEqual(expected, "standard")
                    XCTAssertEqual(actual, "fixed-app-ring")
                default:
                    XCTFail("Expected invalidValue for navigation.mode, got \(configError)")
            }
        }
    }

    func testUnknownConfigKeysAreIgnored() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"
            focus-diagonal = "cmd-k"

            [navigation]
            mode = "standard"
            scope = "all-monitors"
            no-candidate = "anything"
            filtering = "aggressive"
            cycle-timeout-ms = 900
            include-minimized = false
            include-hidden-apps = true

            [hud]
            enabled = true
            show-icons = true
            show-window-count = "yes"
            position = "top-center"
            """
        )

        XCTAssertEqual(cfg.hotkeys.focusLeft, "cmd-left")
        XCTAssertEqual(cfg.hotkeys.focusRight, "cmd-right")
        XCTAssertEqual(cfg.navigation.mode, .standard)
        XCTAssertEqual(cfg.navigation.cycleTimeoutMs, 900)
        XCTAssertFalse(cfg.navigation.includeMinimized)
        XCTAssertTrue(cfg.navigation.includeHiddenApps)
        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertTrue(cfg.hud.showIcons)
        XCTAssertEqual(cfg.hud.position, .topCenter)
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

    func testMissingHUDSectionUsesDefaultHUDValues() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"
            """
        )

        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertTrue(cfg.hud.showIcons)
        XCTAssertEqual(cfg.hud.position, .middleCenter)
    }

    func testParseInvalidNavigationModeThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
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
                    XCTAssertEqual(key, "navigation.mode")
                    XCTAssertEqual(expected, "standard")
                    XCTAssertEqual(actual, "spatial")
                default:
                    XCTFail("Expected invalidValue for navigation.mode, got \(configError)")
            }
        }
    }

    func testParseInvalidStandardUnpinnedAppsThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.standard]
                unpinned-apps = "random"
                """
            )
        )
    }

    func testParseInvalidStandardInAppWindowThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.standard]
                in-app-window = "mru"
                """
            )
        )
    }

    func testParseInvalidStandardGroupingThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.standard]
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

    func testUnknownHUDHideDelayIsLoggedAndIgnored() throws {
        let lines = SinkLines()
        Logger._setTestSink { line in
            lines.append(line)
        }
        defer { Logger._resetForTests() }

        let cfg = try ConfigLoader.parse(
            """
            [hud]
            enabled = true
            hide-delay-ms = 0
            position = "top-center"
            """
        )

        XCTAssertTrue(cfg.hud.enabled)
        XCTAssertTrue(lines.contains("Unknown Key: [hud].hide-delay-ms"))
    }

    func testUnknownKeysAreLogged() throws {
        let lines = SinkLines()
        Logger._setTestSink { line in
            lines.append(line)
        }
        defer { Logger._resetForTests() }

        _ = try ConfigLoader.parse(
            """
            random = 1

            [navigation]
            mode = "standard"
            cycle-timeout-ms = 900
            scope = "all-monitors"

            [navigation.standard]
            pinned-apps = ["com.apple.Terminal"]
            extra = true

            [hotkeys]
            focus-left = "cmd-left"
            focus-right = "cmd-right"
            focus-diagonal = "cmd-k"
            """
        )

        XCTAssertTrue(lines.contains("Unknown Key: [root].random"))
        XCTAssertTrue(lines.contains("Unknown Key: [navigation].scope"))
        XCTAssertTrue(lines.contains("Unknown Key: [navigation.standard].extra"))
        XCTAssertTrue(lines.contains("Unknown Key: [hotkeys].focus-diagonal"))
    }

    func testParseCustomUpDownHotkeys() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hotkeys]
            focus-up = "alt-up"
            focus-down = "alt-down"
            """
        )

        XCTAssertEqual(cfg.hotkeys.focusUp, "alt-up")
        XCTAssertEqual(cfg.hotkeys.focusDown, "alt-down")
    }

    func testParseHUDMiddleCenterPosition() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hud]
            position = "middle-center"
            """
        )

        XCTAssertEqual(cfg.hud.position, .middleCenter)
    }

    func testParseHUDBottomCenterPosition() throws {
        let cfg = try ConfigLoader.parse(
            """
            [hud]
            position = "bottom-center"
            """
        )

        XCTAssertEqual(cfg.hud.position, .bottomCenter)
    }

    func testParseNonArrayPinnedAppsThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation.standard]
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
                cycle-timeout-ms = -1
                """
            )
        )
    }

    func testParseZeroCycleTimeoutDisablesTimeReset() throws {
        let cfg = try ConfigLoader.parse(
            """
            [navigation]
            cycle-timeout-ms = 0
            """
        )

        XCTAssertEqual(cfg.navigation.cycleTimeoutMs, 0)
    }

    func testMissingNavigationModeUsesDefault() throws {
        let cfg = try ConfigLoader.parse(
            """
            [navigation]
            include-hidden-apps = false
            """
        )

        XCTAssertEqual(cfg.navigation.mode, .standard)
        XCTAssertFalse(cfg.navigation.includeHiddenApps)
    }

    func testParseInvalidNavigationIncludeMinimizedTypeThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                include-minimized = "yes"
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }

            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "navigation.include-minimized")
                    XCTAssertEqual(expected, "true|false")
                    XCTAssertEqual(actual, "\"yes\"")
                default:
                    XCTFail("Expected invalidValue for navigation.include-minimized, got \(configError)")
            }
        }
    }

    func testParseInvalidNavigationIncludeHiddenAppsTypeThrowsPreciseError() {
        XCTAssertThrowsError(
            try ConfigLoader.parse(
                """
                [navigation]
                include-hidden-apps = 1
                """
            )
        ) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(type(of: error))")
                return
            }

            switch configError {
                case let .invalidValue(key, expected, actual):
                    XCTAssertEqual(key, "navigation.include-hidden-apps")
                    XCTAssertEqual(expected, "true|false")
                    XCTAssertEqual(actual, "1")
                default:
                    XCTFail("Expected invalidValue for navigation.include-hidden-apps, got \(configError)")
            }
        }
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
