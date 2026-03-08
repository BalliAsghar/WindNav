import Foundation

public struct TabConfig: Equatable, Sendable {
    public var activation: ActivationConfig
    public var directional: DirectionalConfig
    public var onboarding: OnboardingConfig
    public var visibility: VisibilityConfig
    public var ordering: OrderingConfig
    public var filters: FiltersConfig
    public var appearance: AppearanceConfig
    public var performance: PerformanceConfig

    public init(
        activation: ActivationConfig,
        directional: DirectionalConfig,
        onboarding: OnboardingConfig,
        visibility: VisibilityConfig,
        ordering: OrderingConfig,
        filters: FiltersConfig,
        appearance: AppearanceConfig,
        performance: PerformanceConfig
    ) {
        self.activation = activation
        self.directional = directional
        self.onboarding = onboarding
        self.visibility = visibility
        self.ordering = ordering
        self.filters = filters
        self.appearance = appearance
        self.performance = performance
    }

    public static let `default` = TabConfig(
        activation: .default,
        directional: .default,
        onboarding: .default,
        visibility: .default,
        ordering: .default,
        filters: .default,
        appearance: .default,
        performance: .default
    )
}

public struct OnboardingConfig: Equatable, Sendable {
    public var permissionExplainerShown: Bool
    public var launchAtLoginEnabled: Bool

    public init(permissionExplainerShown: Bool, launchAtLoginEnabled: Bool) {
        self.permissionExplainerShown = permissionExplainerShown
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }

    public static let `default` = OnboardingConfig(
        permissionExplainerShown: false,
        launchAtLoginEnabled: false
    )
}

public struct ActivationConfig: Equatable, Sendable {
    public var trigger: String
    public var reverseTrigger: String

    public init(trigger: String, reverseTrigger: String) {
        self.trigger = trigger
        self.reverseTrigger = reverseTrigger
    }

    public static let `default` = ActivationConfig(
        trigger: "cmd-tab",
        reverseTrigger: "cmd-shift-tab"
    )
}

public struct DirectionalConfig: Equatable, Sendable {
    public enum BrowseLeftRightMode: String, Sendable {
        case immediate
        case selection
    }

    public var enabled: Bool
    public var left: String
    public var right: String
    public var up: String
    public var down: String
    public var showThumbnails: Bool
    public var browseLeftRightMode: BrowseLeftRightMode
    public var commitOnModifierRelease: Bool

    public init(
        enabled: Bool,
        left: String,
        right: String,
        up: String,
        down: String,
        showThumbnails: Bool,
        browseLeftRightMode: BrowseLeftRightMode,
        commitOnModifierRelease: Bool
    ) {
        self.enabled = enabled
        self.left = left
        self.right = right
        self.up = up
        self.down = down
        self.showThumbnails = showThumbnails
        self.browseLeftRightMode = browseLeftRightMode
        self.commitOnModifierRelease = commitOnModifierRelease
    }

    public static let `default` = DirectionalConfig(
        enabled: true,
        left: "opt-cmd-left",
        right: "opt-cmd-right",
        up: "opt-cmd-up",
        down: "opt-cmd-down",
        showThumbnails: false,
        browseLeftRightMode: .immediate,
        commitOnModifierRelease: true
    )
}

public struct VisibilityConfig: Equatable, Sendable {
    public enum ShowEmptyAppsPolicy: String, Sendable {
        case hide
        case show
        case showAtEnd = "show-at-end"
    }

    public var showMinimized: Bool
    public var showHidden: Bool
    public var showFullscreen: Bool
    public var showEmptyApps: ShowEmptyAppsPolicy

    public init(
        showMinimized: Bool,
        showHidden: Bool,
        showFullscreen: Bool,
        showEmptyApps: ShowEmptyAppsPolicy
    ) {
        self.showMinimized = showMinimized
        self.showHidden = showHidden
        self.showFullscreen = showFullscreen
        self.showEmptyApps = showEmptyApps
    }

    public static let `default` = VisibilityConfig(
        showMinimized: true,
        showHidden: true,
        showFullscreen: true,
        showEmptyApps: .showAtEnd
    )
}

public enum UnpinnedAppsPolicy: String, Sendable {
    case append
    case ignore
}

public struct OrderingConfig: Equatable, Sendable {
    public var pinnedApps: [String]
    public var unpinnedApps: UnpinnedAppsPolicy

    public init(pinnedApps: [String], unpinnedApps: UnpinnedAppsPolicy) {
        self.pinnedApps = pinnedApps
        self.unpinnedApps = unpinnedApps
    }

    public static let `default` = OrderingConfig(
        pinnedApps: [],
        unpinnedApps: .append
    )
}

public struct FiltersConfig: Equatable, Sendable {
    public var excludeApps: [String]
    public var excludeBundleIds: [String]

    public init(excludeApps: [String], excludeBundleIds: [String]) {
        self.excludeApps = excludeApps
        self.excludeBundleIds = excludeBundleIds
    }

    public static let `default` = FiltersConfig(
        excludeApps: [],
        excludeBundleIds: []
    )
}

public enum ThemeMode: String, Sendable {
    case light
    case dark
    case system
}

public struct AppearanceConfig: Equatable, Sendable {
    public var theme: ThemeMode
    public var iconSize: Int
    public var itemPadding: Int
    public var itemSpacing: Int
    public var showWindowCount: Bool
    public var showThumbnails: Bool
    public var thumbnailWidth: Int

    public init(
        theme: ThemeMode,
        iconSize: Int,
        itemPadding: Int,
        itemSpacing: Int,
        showWindowCount: Bool,
        showThumbnails: Bool,
        thumbnailWidth: Int
    ) {
        self.theme = theme
        self.iconSize = iconSize
        self.itemPadding = itemPadding
        self.itemSpacing = itemSpacing
        self.showWindowCount = showWindowCount
        self.showThumbnails = showThumbnails
        self.thumbnailWidth = thumbnailWidth
    }

    public static let `default` = AppearanceConfig(
        theme: .system,
        iconSize: 22,
        itemPadding: 8,
        itemSpacing: 8,
        showWindowCount: true,
        showThumbnails: true,
        thumbnailWidth: 220
    )
}

public struct PerformanceConfig: Equatable, Sendable {
    public var logLevel: LogLevel
    public var logColor: LogColorMode

    public init(logLevel: LogLevel, logColor: LogColorMode) {
        self.logLevel = logLevel
        self.logColor = logColor
    }

    public static let `default` = PerformanceConfig(logLevel: .info, logColor: .auto)
}

enum ConfigError: LocalizedError, Equatable {
    case invalidToml(String)
    case invalidValue(key: String, expected: String, actual: String)
    case io(String)

    var errorDescription: String? {
        switch self {
            case .invalidToml(let message):
                return "Invalid config TOML: \(message)"
            case .invalidValue(let key, let expected, let actual):
                return "Invalid value for '\(key)'. Expected \(expected), got '\(actual)'"
            case .io(let message):
                return "Config I/O error: \(message)"
        }
    }
}
