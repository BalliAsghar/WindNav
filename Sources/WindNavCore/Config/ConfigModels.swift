import Foundation

public struct WindNavConfig: Equatable, Sendable {
    public var hotkeys: HotkeysConfig
    public var navigation: NavigationConfig
    public var logging: LoggingConfig
    public var startup: StartupConfig
    public var hud: HUDConfig

    public init(
        hotkeys: HotkeysConfig,
        navigation: NavigationConfig,
        logging: LoggingConfig,
        startup: StartupConfig,
        hud: HUDConfig
    ) {
        self.hotkeys = hotkeys
        self.navigation = navigation
        self.logging = logging
        self.startup = startup
        self.hud = hud
    }

    public static let `default` = WindNavConfig(
        hotkeys: .default,
        navigation: .default,
        logging: .default,
        startup: .default,
        hud: .default
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
    public var policy: NavigationPolicy
    public var cycleTimeoutMs: Int
    public var fixedAppRing: FixedAppRingConfig

    public init(
        policy: NavigationPolicy,
        cycleTimeoutMs: Int,
        fixedAppRing: FixedAppRingConfig
    ) {
        self.policy = policy
        self.cycleTimeoutMs = cycleTimeoutMs
        self.fixedAppRing = fixedAppRing
    }

    public static let `default` = NavigationConfig(
        policy: .mruCycle,
        cycleTimeoutMs: 900,
        fixedAppRing: .default
    )
}

public struct FixedAppRingConfig: Equatable, Sendable {
    public var pinnedApps: [String]
    public var unpinnedApps: UnpinnedAppsPolicy
    public var inAppWindow: InAppWindowSelectionPolicy
    public var grouping: GroupingMode

    public init(
        pinnedApps: [String],
        unpinnedApps: UnpinnedAppsPolicy,
        inAppWindow: InAppWindowSelectionPolicy,
        grouping: GroupingMode
    ) {
        self.pinnedApps = pinnedApps
        self.unpinnedApps = unpinnedApps
        self.inAppWindow = inAppWindow
        self.grouping = grouping
    }

    public static let `default` = FixedAppRingConfig(
        pinnedApps: [],
        unpinnedApps: .append,
        inAppWindow: .lastFocused,
        grouping: .oneStopPerApp
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

public struct HUDConfig: Equatable, Sendable {
    public var enabled: Bool
    public var showIcons: Bool
    public var position: HUDPosition

    public init(enabled: Bool, showIcons: Bool, position: HUDPosition) {
        self.enabled = enabled
        self.showIcons = showIcons
        self.position = position
    }

    public static let `default` = HUDConfig(
        enabled: false,
        showIcons: false,
        position: .topCenter
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
    policy = "mru-cycle"
    cycle-timeout-ms = 900
    # Set cycle-timeout-ms = 0 to keep cycling active until the hotkey modifiers are released.

    # To enable predictable app-level cycling:
    # policy = "fixed-app-ring"
    #
    # [navigation.fixed-app-ring]
    # pinned-apps = ["com.google.Chrome", "com.apple.Terminal", "com.microsoft.VSCode"]
    # unpinned-apps = "append"
    # in-app-window = "last-focused"
    # grouping = "one-stop-per-app"

    [logging]
    level = "info"
    color = "auto"

    [startup]
    launch-on-login = false

    [hud]
    enabled = false
    show-icons = false
    position = "top-center"
    """
}
