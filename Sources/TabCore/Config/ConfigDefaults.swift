import Foundation

enum ConfigDefaultValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case stringArray([String])

    var tomlLiteral: String {
        switch self {
            case .string(let value):
                return "\"\(Self.escape(value))\""
            case .int(let value):
                return "\(value)"
            case .bool(let value):
                return value ? "true" : "false"
            case .stringArray(let values):
                let rendered = values.map { "\"\(Self.escape($0))\"" }.joined(separator: ", ")
                return "[\(rendered)]"
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct ConfigSettingSpec: Equatable, Sendable {
    let key: String
    let defaultValue: ConfigDefaultValue
    let allowedValues: String
    let description: String
}

struct ConfigSectionSpec: Equatable, Sendable {
    let name: String
    let settings: [ConfigSettingSpec]
}

enum TabDefaultsCatalog {
    static let activation = ActivationConfig.default
    static let directional = DirectionalConfig.default
    static let onboarding = OnboardingConfig.default
    static let visibility = VisibilityConfig.default
    static let ordering = OrderingConfig.default
    static let filters = FiltersConfig.default
    static let appearance = AppearanceConfig.default
    static let performance = PerformanceConfig.default

    static let config = TabConfig(
        activation: activation,
        directional: directional,
        onboarding: onboarding,
        visibility: visibility,
        ordering: ordering,
        filters: filters,
        appearance: appearance,
        performance: performance
    )

    static let sections: [ConfigSectionSpec] = [
        ConfigSectionSpec(
            name: "activation",
            settings: [
                ConfigSettingSpec(
                    key: "trigger",
                    defaultValue: .string(activation.trigger),
                    allowedValues: "hotkey expression",
                    description: "Forward activation trigger."
                ),
                ConfigSettingSpec(
                    key: "reverse-trigger",
                    defaultValue: .string(activation.reverseTrigger),
                    allowedValues: "hotkey expression",
                    description: "Reverse activation trigger."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "directional",
            settings: [
                ConfigSettingSpec(
                    key: "enabled",
                    defaultValue: .bool(directional.enabled),
                    allowedValues: "true|false",
                    description: "Enable directional navigation hotkeys."
                ),
                ConfigSettingSpec(
                    key: "left",
                    defaultValue: .string(directional.left),
                    allowedValues: "hotkey expression",
                    description: "Navigate left."
                ),
                ConfigSettingSpec(
                    key: "right",
                    defaultValue: .string(directional.right),
                    allowedValues: "hotkey expression",
                    description: "Navigate right."
                ),
                ConfigSettingSpec(
                    key: "up",
                    defaultValue: .string(directional.up),
                    allowedValues: "hotkey expression",
                    description: "Browse up."
                ),
                ConfigSettingSpec(
                    key: "down",
                    defaultValue: .string(directional.down),
                    allowedValues: "hotkey expression",
                    description: "Browse down."
                ),
                ConfigSettingSpec(
                    key: "browse-left-right-mode",
                    defaultValue: .string(directional.browseLeftRightMode.rawValue),
                    allowedValues: "immediate|selection",
                    description: "Whether browse left/right focuses immediately."
                ),
                ConfigSettingSpec(
                    key: "commit-on-modifier-release",
                    defaultValue: .bool(directional.commitOnModifierRelease),
                    allowedValues: "true|false",
                    description: "Commit browse selection on modifier release."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "onboarding",
            settings: [
                ConfigSettingSpec(
                    key: "permission-explainer-shown",
                    defaultValue: .bool(onboarding.permissionExplainerShown),
                    allowedValues: "true|false",
                    description: "Tracks first-run onboarding alert."
                ),
                ConfigSettingSpec(
                    key: "launch-at-login-enabled",
                    defaultValue: .bool(onboarding.launchAtLoginEnabled),
                    allowedValues: "true|false",
                    description: "Whether WindNav should launch automatically at login."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "visibility",
            settings: [
                ConfigSettingSpec(
                    key: "show-minimized",
                    defaultValue: .bool(visibility.showMinimized),
                    allowedValues: "true|false",
                    description: "Include minimized windows."
                ),
                ConfigSettingSpec(
                    key: "show-hidden",
                    defaultValue: .bool(visibility.showHidden),
                    allowedValues: "true|false",
                    description: "Include hidden apps."
                ),
                ConfigSettingSpec(
                    key: "show-fullscreen",
                    defaultValue: .bool(visibility.showFullscreen),
                    allowedValues: "true|false",
                    description: "Include fullscreen windows."
                ),
                ConfigSettingSpec(
                    key: "show-empty-apps",
                    defaultValue: .string(visibility.showEmptyApps.rawValue),
                    allowedValues: "hide|show|show-at-end",
                    description: "How to include apps without windows."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "ordering",
            settings: [
                ConfigSettingSpec(
                    key: "pinned-apps",
                    defaultValue: .stringArray(ordering.pinnedApps),
                    allowedValues: "array of bundle identifiers",
                    description: "App bundle IDs pinned to the front."
                ),
                ConfigSettingSpec(
                    key: "unpinned-apps",
                    defaultValue: .string(ordering.unpinnedApps.rawValue),
                    allowedValues: "append|ignore",
                    description: "How to handle unpinned apps."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "filters",
            settings: [
                ConfigSettingSpec(
                    key: "exclude-apps",
                    defaultValue: .stringArray(filters.excludeApps),
                    allowedValues: "array of app names",
                    description: "Case-insensitive app names to exclude."
                ),
                ConfigSettingSpec(
                    key: "exclude-bundle-ids",
                    defaultValue: .stringArray(filters.excludeBundleIds),
                    allowedValues: "array of bundle identifiers",
                    description: "Case-insensitive bundle IDs to exclude."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "appearance",
            settings: [
                ConfigSettingSpec(
                    key: "theme",
                    defaultValue: .string(appearance.theme.rawValue),
                    allowedValues: "light|dark|system",
                    description: "HUD theme mode."
                ),
                ConfigSettingSpec(
                    key: "icon-size",
                    defaultValue: .int(appearance.iconSize),
                    allowedValues: "integer 14...64",
                    description: "HUD icon size in points."
                ),
                ConfigSettingSpec(
                    key: "item-padding",
                    defaultValue: .int(appearance.itemPadding),
                    allowedValues: "integer 0...24",
                    description: "HUD item padding."
                ),
                ConfigSettingSpec(
                    key: "item-spacing",
                    defaultValue: .int(appearance.itemSpacing),
                    allowedValues: "integer 0...24",
                    description: "HUD item spacing."
                ),
                ConfigSettingSpec(
                    key: "show-window-count",
                    defaultValue: .bool(appearance.showWindowCount),
                    allowedValues: "true|false",
                    description: "Show in-app window index badges."
                ),
                ConfigSettingSpec(
                    key: "show-thumbnails",
                    defaultValue: .bool(appearance.showThumbnails),
                    allowedValues: "true|false",
                    description: "Show live window thumbnails in the HUD."
                ),
                ConfigSettingSpec(
                    key: "thumbnail-width",
                    defaultValue: .int(appearance.thumbnailWidth),
                    allowedValues: "integer 120...320",
                    description: "Target thumbnail width in points."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "performance",
            settings: [
                ConfigSettingSpec(
                    key: "log-level",
                    defaultValue: .string(performance.logLevel.rawValue),
                    allowedValues: "debug|info|error",
                    description: "Minimum log level."
                ),
                ConfigSettingSpec(
                    key: "log-color",
                    defaultValue: .string(performance.logColor.rawValue),
                    allowedValues: "auto|always|never",
                    description: "ANSI color output mode."
                ),
            ]
        ),
    ]

    static let renderedToml = renderToml(sections: sections)

    private static func renderToml(sections: [ConfigSectionSpec]) -> String {
        var lines: [String] = []

        for (index, section) in sections.enumerated() {
            lines.append("[\(section.name)]")
            for setting in section.settings {
                lines.append("# \(setting.description)")
                lines.append("# Allowed: \(setting.allowedValues)")
                lines.append("# Default: \(setting.defaultValue.tomlLiteral)")
                lines.append("\(setting.key) = \(setting.defaultValue.tomlLiteral)")
                lines.append("")
            }

            if lines.last == "" {
                _ = lines.popLast()
            }

            if index < sections.count - 1 {
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension TabConfig {
    static let defaultToml = TabDefaultsCatalog.renderedToml
}
