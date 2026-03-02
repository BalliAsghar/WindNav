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

enum WindNavDefaultsCatalog {
    static let hotkeys = HotkeysConfig(
        focusLeft: "cmd-left",
        focusRight: "cmd-right",
        focusUp: "cmd-up",
        focusDown: "cmd-down",
        browseNext: "cmd-tab",
        browsePrevious: "cmd-shift-tab"
    )

    static let fixedAppRing = FixedAppRingConfig(
        pinnedApps: [],
        unpinnedApps: .append,
        inAppWindow: .lastFocused,
        grouping: .oneStopPerApp
    )

    static let navigation = NavigationConfig(
        mode: .standard,
        cycleTimeoutMs: 900,
        includeMinimized: true,
        includeHiddenApps: true,
        showWindowlessApps: .hide,
        fixedAppRing: fixedAppRing
    )

    static let logging = LoggingConfig(
        level: .info,
        color: .auto
    )

    static let startup = StartupConfig(
        launchOnLogin: false
    )

    static let hud = HUDConfig(
        enabled: true,
        showIcons: true,
        iconSize: 22,
        position: .middleCenter
    )

    static let config = WindNavConfig(
        hotkeys: hotkeys,
        navigation: navigation,
        logging: logging,
        startup: startup,
        hud: hud
    )

    static let sections: [ConfigSectionSpec] = [
        ConfigSectionSpec(
            name: "hotkeys",
            settings: [
                ConfigSettingSpec(
                    key: "focus-left",
                    defaultValue: .string(hotkeys.focusLeft),
                    allowedValues: "modifiers cmd|command|opt|option|alt|ctrl|control|ctl|shift + key token",
                    description: "Move focus to the previous app/window target."
                ),
                ConfigSettingSpec(
                    key: "focus-right",
                    defaultValue: .string(hotkeys.focusRight),
                    allowedValues: "modifiers cmd|command|opt|option|alt|ctrl|control|ctl|shift + key token",
                    description: "Move focus to the next app/window target."
                ),
                ConfigSettingSpec(
                    key: "focus-up",
                    defaultValue: .string(hotkeys.focusUp),
                    allowedValues: "modifiers cmd|command|opt|option|alt|ctrl|control|ctl|shift + key token",
                    description: "Open the browse HUD; when browsing, move to the next window in the selected app."
                ),
                ConfigSettingSpec(
                    key: "focus-down",
                    defaultValue: .string(hotkeys.focusDown),
                    allowedValues: "modifiers cmd|command|opt|option|alt|ctrl|control|ctl|shift + key token",
                    description: "Open the browse HUD; when browsing, move to the previous window in the selected app."
                ),
                ConfigSettingSpec(
                    key: "browse-next",
                    defaultValue: .string(hotkeys.browseNext),
                    allowedValues: "modifiers cmd|command|opt|option|alt|ctrl|control|ctl|shift + key token",
                    description: "Open the browse HUD or cycle to the next app while browsing."
                ),
                ConfigSettingSpec(
                    key: "browse-previous",
                    defaultValue: .string(hotkeys.browsePrevious),
                    allowedValues: "modifiers cmd|command|opt|option|alt|ctrl|control|ctl|shift + key token",
                    description: "Open the browse HUD or cycle to the previous app while browsing (Shift+Tab)."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "navigation",
            settings: [
                ConfigSettingSpec(
                    key: "mode",
                    defaultValue: .string(navigation.mode.rawValue),
                    allowedValues: "standard",
                    description: "Navigation strategy for directional cycling."
                ),
                ConfigSettingSpec(
                    key: "cycle-timeout-ms",
                    defaultValue: .int(navigation.cycleTimeoutMs),
                    allowedValues: "non-negative integer (0 disables timeout reset)",
                    description: "Cycling session timeout in milliseconds."
                ),
                ConfigSettingSpec(
                    key: "include-minimized",
                    defaultValue: .bool(navigation.includeMinimized),
                    allowedValues: "true|false",
                    description: "Whether minimized windows should be included in navigation."
                ),
                ConfigSettingSpec(
                    key: "include-hidden-apps",
                    defaultValue: .bool(navigation.includeHiddenApps),
                    allowedValues: "true|false",
                    description: "Whether app windows from hidden apps should be included in navigation."
                ),
                ConfigSettingSpec(
                    key: "show-windowless-apps",
                    defaultValue: .string(navigation.showWindowlessApps.rawValue),
                    allowedValues: "hide|show|show-at-end",
                    description: "Whether apps with no open windows should be shown. Only accessible in browse flow (cmd+up/down)."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "navigation.standard",
            settings: [
                ConfigSettingSpec(
                    key: "pinned-apps",
                    defaultValue: .stringArray(fixedAppRing.pinnedApps),
                    allowedValues: "array of bundle identifiers",
                    description: "Apps to prioritize first in the navigation order."
                ),
                ConfigSettingSpec(
                    key: "unpinned-apps",
                    defaultValue: .string(fixedAppRing.unpinnedApps.rawValue),
                    allowedValues: "append|ignore",
                    description: "How to include apps that are not listed in pinned-apps."
                ),
                ConfigSettingSpec(
                    key: "in-app-window",
                    defaultValue: .string(fixedAppRing.inAppWindow.rawValue),
                    allowedValues: "last-focused|last-focused-on-monitor|spatial",
                    description: "Window selection strategy within the selected app."
                ),
                ConfigSettingSpec(
                    key: "grouping",
                    defaultValue: .string(fixedAppRing.grouping.rawValue),
                    allowedValues: "one-stop-per-app",
                    description: "Grouping mode for app-level traversal."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "logging",
            settings: [
                ConfigSettingSpec(
                    key: "level",
                    defaultValue: .string(logging.level.rawValue),
                    allowedValues: "info|error",
                    description: "Minimum log level written to stdout."
                ),
                ConfigSettingSpec(
                    key: "color",
                    defaultValue: .string(logging.color.rawValue),
                    allowedValues: "auto|always|never",
                    description: "ANSI color mode for logs."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "startup",
            settings: [
                ConfigSettingSpec(
                    key: "launch-on-login",
                    defaultValue: .bool(startup.launchOnLogin),
                    allowedValues: "true|false",
                    description: "Whether WindNav should register itself to launch at login."
                ),
            ]
        ),
        ConfigSectionSpec(
            name: "hud",
            settings: [
                ConfigSettingSpec(
                    key: "enabled",
                    defaultValue: .bool(hud.enabled),
                    allowedValues: "true|false",
                    description: "Whether to show the cycle HUD while navigating."
                ),
                ConfigSettingSpec(
                    key: "show-icons",
                    defaultValue: .bool(hud.showIcons),
                    allowedValues: "true|false",
                    description: "Whether app icons are shown in the HUD."
                ),
                ConfigSettingSpec(
                    key: "icon-size",
                    defaultValue: .int(hud.iconSize),
                    allowedValues: "positive integer pixels",
                    description: "Pixel size for app icons shown in the HUD."
                ),
                ConfigSettingSpec(
                    key: "position",
                    defaultValue: .string(hud.position.rawValue),
                    allowedValues: "top-center|middle-center|bottom-center",
                    description: "HUD anchor position on the active screen."
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
