import Foundation

public struct WindNavConfig: Equatable, Sendable {
    public var hotkeys: HotkeysConfig
    public var navigation: NavigationConfig
    public var logging: LoggingConfig
    public var startup: StartupConfig

    public init(hotkeys: HotkeysConfig, navigation: NavigationConfig, logging: LoggingConfig, startup: StartupConfig) {
        self.hotkeys = hotkeys
        self.navigation = navigation
        self.logging = logging
        self.startup = startup
    }

    public static let `default` = WindNavConfig(
        hotkeys: .default,
        navigation: .default,
        logging: .default,
        startup: .default
    )
}

public struct HotkeysConfig: Equatable, Sendable {
    public var focusLeft: String
    public var focusRight: String

    public init(focusLeft: String, focusRight: String) {
        self.focusLeft = focusLeft
        self.focusRight = focusRight
    }

    public static let `default` = HotkeysConfig(
        focusLeft: "cmd-left",
        focusRight: "cmd-right"
    )
}

public struct NavigationConfig: Equatable, Sendable {
    public var scope: NavigationScope
    public var policy: NavigationPolicy
    public var noCandidate: NoCandidateBehavior
    public var filtering: FilteringMode
    public var cycleTimeoutMs: Int

    public init(
        scope: NavigationScope,
        policy: NavigationPolicy,
        noCandidate: NoCandidateBehavior,
        filtering: FilteringMode,
        cycleTimeoutMs: Int
    ) {
        self.scope = scope
        self.policy = policy
        self.noCandidate = noCandidate
        self.filtering = filtering
        self.cycleTimeoutMs = cycleTimeoutMs
    }

    public static let `default` = NavigationConfig(
        scope: .currentMonitor,
        policy: .mruCycle,
        noCandidate: .noop,
        filtering: .conservative,
        cycleTimeoutMs: 900
    )
}

public struct LoggingConfig: Equatable, Sendable {
    public var level: LogLevel
    public var color: LogColorMode

    public init(level: LogLevel, color: LogColorMode) {
        self.level = level
        self.color = color
    }

    public static let `default` = LoggingConfig(
        level: .info,
        color: .auto
    )
}

public struct StartupConfig: Equatable, Sendable {
    public var launchOnLogin: Bool

    public init(launchOnLogin: Bool) {
        self.launchOnLogin = launchOnLogin
    }

    public static let `default` = StartupConfig(
        launchOnLogin: false
    )
}

enum ConfigError: LocalizedError, Equatable {
    case invalidToml(String)
    case invalidValue(key: String, expected: String, actual: String)
    case io(String)

    var errorDescription: String? {
        switch self {
            case .invalidToml(let message):
                return "Invalid config TOML: \(message)"
            case let .invalidValue(key, expected, actual):
                return "Invalid value for '\(key)'. Expected \(expected), got '\(actual)'"
            case .io(let message):
                return "Config I/O error: \(message)"
        }
    }
}

extension WindNavConfig {
    static let defaultToml = """
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
    launch-on-login = false
    """
}
