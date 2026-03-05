import Foundation
import TOMLKit

final class ConfigLoader {
    let configURL: URL

    init(configURL: URL = ConfigLoader.defaultConfigURL()) {
        self.configURL = configURL
    }

    static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: "windnav", directoryHint: .isDirectory)
            .appending(path: "config.toml", directoryHint: .notDirectory)
    }

    func loadOrCreate() throws -> TabConfig {
        try ensureExists()

        let text: String
        do {
            text = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw ConfigError.io(error.localizedDescription)
        }

        return try Self.parse(text)
    }

    func save(_ config: TabConfig) throws {
        try Self.validate(config)
        try ensureExists()

        let text = Self.serialize(config)
        do {
            try text.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigError.io(error.localizedDescription)
        }
    }

    private func ensureExists() throws {
        let dir = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configURL.path) {
                try TabConfig.defaultToml.write(to: configURL, atomically: true, encoding: .utf8)
            }
        } catch {
            throw ConfigError.io(error.localizedDescription)
        }
    }

    static func parse(_ text: String) throws -> TabConfig {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: text)
        } catch let parse as TOMLParseError {
            throw ConfigError.invalidToml(parse.debugDescription)
        } catch {
            throw ConfigError.invalidToml(error.localizedDescription)
        }

        var activation = ActivationConfig.default
        var directional = DirectionalConfig.default
        var onboarding = OnboardingConfig.default
        var visibility = VisibilityConfig.default
        var ordering = OrderingConfig.default
        var filters = FiltersConfig.default
        var appearance = AppearanceConfig.default
        var performance = PerformanceConfig.default

        logUnknownKeys(in: table, section: "root", known: [
            "activation", "directional", "onboarding", "visibility", "ordering", "filters", "appearance", "performance",
        ])

        if let activationTable = table["activation"]?.table {
            logUnknownKeys(in: activationTable, section: "activation", known: [
                "trigger", "reverse-trigger", "override-system-cmd-tab",
            ])
            activation.trigger = try parseStringIfPresent(
                table: activationTable,
                key: "trigger",
                section: "activation",
                defaultValue: activation.trigger
            )
            activation.reverseTrigger = try parseStringIfPresent(
                table: activationTable,
                key: "reverse-trigger",
                section: "activation",
                defaultValue: activation.reverseTrigger
            )
            activation.overrideSystemCmdTab = try parseBoolIfPresent(
                table: activationTable,
                key: "override-system-cmd-tab",
                section: "activation",
                defaultValue: activation.overrideSystemCmdTab
            )
        }

        if let directionalTable = table["directional"]?.table {
            logUnknownKeys(in: directionalTable, section: "directional", known: [
                "enabled", "left", "right", "up", "down", "browse-left-right-mode", "commit-on-modifier-release",
            ])
            directional.enabled = try parseBoolIfPresent(
                table: directionalTable,
                key: "enabled",
                section: "directional",
                defaultValue: directional.enabled
            )
            directional.left = try parseStringIfPresent(
                table: directionalTable,
                key: "left",
                section: "directional",
                defaultValue: directional.left
            )
            directional.right = try parseStringIfPresent(
                table: directionalTable,
                key: "right",
                section: "directional",
                defaultValue: directional.right
            )
            directional.up = try parseStringIfPresent(
                table: directionalTable,
                key: "up",
                section: "directional",
                defaultValue: directional.up
            )
            directional.down = try parseStringIfPresent(
                table: directionalTable,
                key: "down",
                section: "directional",
                defaultValue: directional.down
            )

            if let modeRaw = directionalTable["browse-left-right-mode"]?.string {
                guard let mode = DirectionalConfig.BrowseLeftRightMode(rawValue: modeRaw) else {
                    throw ConfigError.invalidValue(
                        key: "directional.browse-left-right-mode",
                        expected: "immediate|selection",
                        actual: modeRaw
                    )
                }
                directional.browseLeftRightMode = mode
            } else if let raw = directionalTable["browse-left-right-mode"] {
                throw ConfigError.invalidValue(
                    key: "directional.browse-left-right-mode",
                    expected: "immediate|selection",
                    actual: renderedValue(raw)
                )
            }

            directional.commitOnModifierRelease = try parseBoolIfPresent(
                table: directionalTable,
                key: "commit-on-modifier-release",
                section: "directional",
                defaultValue: directional.commitOnModifierRelease
            )
        }

        if let onboardingTable = table["onboarding"]?.table {
            logUnknownKeys(in: onboardingTable, section: "onboarding", known: [
                "permission-explainer-shown",
                "launch-at-login-enabled",
            ])
            onboarding.permissionExplainerShown = try parseBoolIfPresent(
                table: onboardingTable,
                key: "permission-explainer-shown",
                section: "onboarding",
                defaultValue: onboarding.permissionExplainerShown
            )
            onboarding.launchAtLoginEnabled = try parseBoolIfPresent(
                table: onboardingTable,
                key: "launch-at-login-enabled",
                section: "onboarding",
                defaultValue: onboarding.launchAtLoginEnabled
            )
        }

        if let visibilityTable = table["visibility"]?.table {
            logUnknownKeys(in: visibilityTable, section: "visibility", known: [
                "show-minimized", "show-hidden", "show-fullscreen", "show-empty-apps",
            ])
            visibility.showMinimized = try parseBoolIfPresent(
                table: visibilityTable,
                key: "show-minimized",
                section: "visibility",
                defaultValue: visibility.showMinimized
            )
            visibility.showHidden = try parseBoolIfPresent(
                table: visibilityTable,
                key: "show-hidden",
                section: "visibility",
                defaultValue: visibility.showHidden
            )
            visibility.showFullscreen = try parseBoolIfPresent(
                table: visibilityTable,
                key: "show-fullscreen",
                section: "visibility",
                defaultValue: visibility.showFullscreen
            )

            if let showEmptyAppsRaw = visibilityTable["show-empty-apps"]?.string {
                guard let policy = VisibilityConfig.ShowEmptyAppsPolicy(rawValue: showEmptyAppsRaw) else {
                    throw ConfigError.invalidValue(
                        key: "visibility.show-empty-apps",
                        expected: "hide|show|show-at-end",
                        actual: showEmptyAppsRaw
                    )
                }
                visibility.showEmptyApps = policy
            } else if let raw = visibilityTable["show-empty-apps"] {
                throw ConfigError.invalidValue(
                    key: "visibility.show-empty-apps",
                    expected: "hide|show|show-at-end",
                    actual: renderedValue(raw)
                )
            }
        }

        if let orderingTable = table["ordering"]?.table {
            logUnknownKeys(in: orderingTable, section: "ordering", known: [
                "pinned-apps", "unpinned-apps",
            ])

            ordering.pinnedApps = dedupe(
                try parseStringArrayIfPresent(
                    table: orderingTable,
                    key: "pinned-apps",
                    section: "ordering",
                    defaultValue: ordering.pinnedApps
                )
            )

            if let unpinnedRaw = orderingTable["unpinned-apps"]?.string {
                guard let policy = UnpinnedAppsPolicy(rawValue: unpinnedRaw) else {
                    throw ConfigError.invalidValue(
                        key: "ordering.unpinned-apps",
                        expected: "append|ignore",
                        actual: unpinnedRaw
                    )
                }
                ordering.unpinnedApps = policy
            } else if let raw = orderingTable["unpinned-apps"] {
                throw ConfigError.invalidValue(
                    key: "ordering.unpinned-apps",
                    expected: "append|ignore",
                    actual: renderedValue(raw)
                )
            }
        }

        if let filtersTable = table["filters"]?.table {
            logUnknownKeys(in: filtersTable, section: "filters", known: [
                "exclude-apps", "exclude-bundle-ids",
            ])
            filters.excludeApps = dedupe(
                try parseStringArrayIfPresent(
                    table: filtersTable,
                    key: "exclude-apps",
                    section: "filters",
                    defaultValue: filters.excludeApps
                )
            )
            filters.excludeBundleIds = dedupe(
                try parseStringArrayIfPresent(
                    table: filtersTable,
                    key: "exclude-bundle-ids",
                    section: "filters",
                    defaultValue: filters.excludeBundleIds
                )
            )
        }

        if let appearanceTable = table["appearance"]?.table {
            logUnknownKeys(in: appearanceTable, section: "appearance", known: [
                "theme", "icon-size", "item-padding", "item-spacing", "show-window-count",
                "show-thumbnails", "thumbnail-width",
            ])

            if let themeRaw = appearanceTable["theme"]?.string {
                guard let theme = ThemeMode(rawValue: themeRaw) else {
                    throw ConfigError.invalidValue(
                        key: "appearance.theme",
                        expected: "light|dark|system",
                        actual: themeRaw
                    )
                }
                appearance.theme = theme
            } else if let raw = appearanceTable["theme"] {
                throw ConfigError.invalidValue(
                    key: "appearance.theme",
                    expected: "light|dark|system",
                    actual: renderedValue(raw)
                )
            }

            appearance.iconSize = try parseIntIfPresent(
                table: appearanceTable,
                key: "icon-size",
                section: "appearance",
                defaultValue: appearance.iconSize
            )
            appearance.itemPadding = try parseIntIfPresent(
                table: appearanceTable,
                key: "item-padding",
                section: "appearance",
                defaultValue: appearance.itemPadding
            )
            appearance.itemSpacing = try parseIntIfPresent(
                table: appearanceTable,
                key: "item-spacing",
                section: "appearance",
                defaultValue: appearance.itemSpacing
            )
            appearance.showWindowCount = try parseBoolIfPresent(
                table: appearanceTable,
                key: "show-window-count",
                section: "appearance",
                defaultValue: appearance.showWindowCount
            )
            appearance.showThumbnails = try parseBoolIfPresent(
                table: appearanceTable,
                key: "show-thumbnails",
                section: "appearance",
                defaultValue: appearance.showThumbnails
            )
            appearance.thumbnailWidth = try parseIntIfPresent(
                table: appearanceTable,
                key: "thumbnail-width",
                section: "appearance",
                defaultValue: appearance.thumbnailWidth
            )
        }

        if let performanceTable = table["performance"]?.table {
            logUnknownKeys(in: performanceTable, section: "performance", known: [
                "log-level", "log-color",
            ])

            if let logRaw = performanceTable["log-level"]?.string {
                guard let level = LogLevel(rawValue: logRaw) else {
                    throw ConfigError.invalidValue(
                        key: "performance.log-level",
                        expected: "debug|info|error",
                        actual: logRaw
                    )
                }
                performance.logLevel = level
            } else if let raw = performanceTable["log-level"] {
                throw ConfigError.invalidValue(
                    key: "performance.log-level",
                    expected: "debug|info|error",
                    actual: renderedValue(raw)
                )
            }

            if let colorRaw = performanceTable["log-color"]?.string {
                guard let color = LogColorMode(rawValue: colorRaw) else {
                    throw ConfigError.invalidValue(
                        key: "performance.log-color",
                        expected: "auto|always|never",
                        actual: colorRaw
                    )
                }
                performance.logColor = color
            } else if let raw = performanceTable["log-color"] {
                throw ConfigError.invalidValue(
                    key: "performance.log-color",
                    expected: "auto|always|never",
                    actual: renderedValue(raw)
                )
            }
        }

        let config = TabConfig(
            activation: activation,
            directional: directional,
            onboarding: onboarding,
            visibility: visibility,
            ordering: ordering,
            filters: filters,
            appearance: appearance,
            performance: performance
        )
        try validate(config)
        return config
    }

    static func serialize(_ config: TabConfig) -> String {
        let pinnedApps = serializeStringArray(config.ordering.pinnedApps)
        let excludeApps = serializeStringArray(config.filters.excludeApps)
        let excludeBundleIDs = serializeStringArray(config.filters.excludeBundleIds)

        return """
        [activation]
        trigger = "\(escape(config.activation.trigger))"
        reverse-trigger = "\(escape(config.activation.reverseTrigger))"
        override-system-cmd-tab = \(config.activation.overrideSystemCmdTab)

        [directional]
        enabled = \(config.directional.enabled)
        left = "\(escape(config.directional.left))"
        right = "\(escape(config.directional.right))"
        up = "\(escape(config.directional.up))"
        down = "\(escape(config.directional.down))"
        browse-left-right-mode = "\(config.directional.browseLeftRightMode.rawValue)"
        commit-on-modifier-release = \(config.directional.commitOnModifierRelease)

        [onboarding]
        permission-explainer-shown = \(config.onboarding.permissionExplainerShown)
        launch-at-login-enabled = \(config.onboarding.launchAtLoginEnabled)

        [visibility]
        show-minimized = \(config.visibility.showMinimized)
        show-hidden = \(config.visibility.showHidden)
        show-fullscreen = \(config.visibility.showFullscreen)
        show-empty-apps = "\(config.visibility.showEmptyApps.rawValue)"

        [ordering]
        pinned-apps = \(pinnedApps)
        unpinned-apps = "\(config.ordering.unpinnedApps.rawValue)"

        [filters]
        exclude-apps = \(excludeApps)
        exclude-bundle-ids = \(excludeBundleIDs)

        [appearance]
        theme = "\(config.appearance.theme.rawValue)"
        icon-size = \(config.appearance.iconSize)
        item-padding = \(config.appearance.itemPadding)
        item-spacing = \(config.appearance.itemSpacing)
        show-window-count = \(config.appearance.showWindowCount)
        show-thumbnails = \(config.appearance.showThumbnails)
        thumbnail-width = \(config.appearance.thumbnailWidth)

        [performance]
        log-level = "\(config.performance.logLevel.rawValue)"
        log-color = "\(config.performance.logColor.rawValue)"
        """
    }

    private static func validate(_ config: TabConfig) throws {
        if !(14...64).contains(config.appearance.iconSize) {
            throw ConfigError.invalidValue(
                key: "appearance.icon-size",
                expected: "integer in range 14...64",
                actual: "\(config.appearance.iconSize)"
            )
        }

        if !(0...24).contains(config.appearance.itemPadding) {
            throw ConfigError.invalidValue(
                key: "appearance.item-padding",
                expected: "integer in range 0...24",
                actual: "\(config.appearance.itemPadding)"
            )
        }

        if !(0...24).contains(config.appearance.itemSpacing) {
            throw ConfigError.invalidValue(
                key: "appearance.item-spacing",
                expected: "integer in range 0...24",
                actual: "\(config.appearance.itemSpacing)"
            )
        }

        if !(120...320).contains(config.appearance.thumbnailWidth) {
            throw ConfigError.invalidValue(
                key: "appearance.thumbnail-width",
                expected: "integer in range 120...320",
                actual: "\(config.appearance.thumbnailWidth)"
            )
        }
    }

    private static func parseStringIfPresent(
        table: TOMLTable,
        key: String,
        section: String,
        defaultValue: String
    ) throws -> String {
        if let value = table[key]?.string {
            return value
        }
        if let raw = table[key] {
            throw ConfigError.invalidValue(key: "\(section).\(key)", expected: "string", actual: renderedValue(raw))
        }
        return defaultValue
    }

    private static func parseBoolIfPresent(
        table: TOMLTable,
        key: String,
        section: String,
        defaultValue: Bool
    ) throws -> Bool {
        if let value = table[key]?.bool {
            return value
        }
        if let raw = table[key] {
            throw ConfigError.invalidValue(key: "\(section).\(key)", expected: "true|false", actual: renderedValue(raw))
        }
        return defaultValue
    }

    private static func parseIntIfPresent(
        table: TOMLTable,
        key: String,
        section: String,
        defaultValue: Int
    ) throws -> Int {
        if let value = table[key]?.int {
            return value
        }
        if let raw = table[key] {
            throw ConfigError.invalidValue(key: "\(section).\(key)", expected: "integer", actual: renderedValue(raw))
        }
        return defaultValue
    }

    private static func parseStringArrayIfPresent(
        table: TOMLTable,
        key: String,
        section: String,
        defaultValue: [String]
    ) throws -> [String] {
        guard let rawArray = table[key]?.array else {
            if let raw = table[key] {
                throw ConfigError.invalidValue(key: "\(section).\(key)", expected: "array of strings", actual: renderedValue(raw))
            }
            return defaultValue
        }

        var parsed: [String] = []
        for element in rawArray {
            guard let value = element.string else {
                throw ConfigError.invalidValue(
                    key: "\(section).\(key)",
                    expected: "array of strings",
                    actual: renderedValue(element)
                )
            }
            parsed.append(value)
        }
        return parsed
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            out.append(value)
        }
        return out
    }

    private static func renderedValue(_ value: any TOMLValueConvertible) -> String {
        String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func serializeStringArray(_ values: [String]) -> String {
        let rendered = values.map { "\"\(escape($0))\"" }.joined(separator: ", ")
        return "[\(rendered)]"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func logUnknownKeys(in table: TOMLTable, section: String, known: Set<String>) {
        let unknown = table.keys.filter { !known.contains($0) }.sorted()
        for key in unknown {
            Logger.info(.config, "Unknown key ignored: [\(section)].\(key)")
        }
    }
}
