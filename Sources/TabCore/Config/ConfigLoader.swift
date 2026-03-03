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
            .appending(path: "tabpp", directoryHint: .isDirectory)
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
        var visibility = VisibilityConfig.default
        var ordering = OrderingConfig.default
        var filters = FiltersConfig.default
        var appearance = AppearanceConfig.default
        var performance = PerformanceConfig.default

        logUnknownKeys(in: table, section: "root", known: [
            "activation", "directional", "visibility", "ordering", "filters", "appearance", "performance",
        ])

        if let activationTable = table["activation"]?.table {
            logUnknownKeys(in: activationTable, section: "activation", known: [
                "trigger", "reverse-trigger", "override-system-cmd-tab",
            ])
            if let value = activationTable["trigger"]?.string {
                activation.trigger = value
            } else if let raw = activationTable["trigger"] {
                throw ConfigError.invalidValue(key: "activation.trigger", expected: "string", actual: renderedValue(raw))
            }

            if let value = activationTable["reverse-trigger"]?.string {
                activation.reverseTrigger = value
            } else if let raw = activationTable["reverse-trigger"] {
                throw ConfigError.invalidValue(key: "activation.reverse-trigger", expected: "string", actual: renderedValue(raw))
            }

            if let value = activationTable["override-system-cmd-tab"]?.bool {
                activation.overrideSystemCmdTab = value
            } else if let raw = activationTable["override-system-cmd-tab"] {
                throw ConfigError.invalidValue(key: "activation.override-system-cmd-tab", expected: "true|false", actual: renderedValue(raw))
            }
        }

        if let directionalTable = table["directional"]?.table {
            logUnknownKeys(in: directionalTable, section: "directional", known: [
                "enabled", "left", "right", "up", "down", "browse-left-right-mode", "commit-on-modifier-release",
            ])

            if let value = directionalTable["enabled"]?.bool {
                directional.enabled = value
            } else if let raw = directionalTable["enabled"] {
                throw ConfigError.invalidValue(key: "directional.enabled", expected: "true|false", actual: renderedValue(raw))
            }

            directional.left = try parseStringIfPresent(table: directionalTable, key: "left", section: "directional", defaultValue: directional.left)
            directional.right = try parseStringIfPresent(table: directionalTable, key: "right", section: "directional", defaultValue: directional.right)
            directional.up = try parseStringIfPresent(table: directionalTable, key: "up", section: "directional", defaultValue: directional.up)
            directional.down = try parseStringIfPresent(table: directionalTable, key: "down", section: "directional", defaultValue: directional.down)
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

            if let value = directionalTable["commit-on-modifier-release"]?.bool {
                directional.commitOnModifierRelease = value
            } else if let raw = directionalTable["commit-on-modifier-release"] {
                throw ConfigError.invalidValue(key: "directional.commit-on-modifier-release", expected: "true|false", actual: renderedValue(raw))
            }
        }

        if let visibilityTable = table["visibility"]?.table {
            logUnknownKeys(in: visibilityTable, section: "visibility", known: [
                "show-minimized", "show-hidden", "show-fullscreen", "show-empty-apps",
            ])

            visibility.showMinimized = try parseBoolIfPresent(table: visibilityTable, key: "show-minimized", section: "visibility", defaultValue: visibility.showMinimized)
            visibility.showHidden = try parseBoolIfPresent(table: visibilityTable, key: "show-hidden", section: "visibility", defaultValue: visibility.showHidden)
            visibility.showFullscreen = try parseBoolIfPresent(table: visibilityTable, key: "show-fullscreen", section: "visibility", defaultValue: visibility.showFullscreen)
            if let raw = visibilityTable["show-empty-apps"]?.string {
                guard let policy = VisibilityConfig.ShowEmptyAppsPolicy(rawValue: raw) else {
                    throw ConfigError.invalidValue(
                        key: "visibility.show-empty-apps",
                        expected: "hide|show|show-at-end",
                        actual: raw
                    )
                }
                visibility.showEmptyApps = policy
            } else if let raw = visibilityTable["show-empty-apps"]?.bool {
                visibility.showEmptyApps = raw ? .show : .hide
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
                "mode", "fixed-apps", "pinned-apps", "unpinned-apps",
            ])

            if let modeRaw = orderingTable["mode"]?.string {
                guard let mode = OrderingMode(rawValue: modeRaw) else {
                    throw ConfigError.invalidValue(key: "ordering.mode", expected: "fixed|most-recent|pinned", actual: modeRaw)
                }
                ordering.mode = mode
            } else if let raw = orderingTable["mode"] {
                throw ConfigError.invalidValue(key: "ordering.mode", expected: "fixed|most-recent|pinned", actual: renderedValue(raw))
            }

            if let policyRaw = orderingTable["unpinned-apps"]?.string {
                guard let policy = UnpinnedAppsPolicy(rawValue: policyRaw) else {
                    throw ConfigError.invalidValue(key: "ordering.unpinned-apps", expected: "append|ignore", actual: policyRaw)
                }
                ordering.unpinnedApps = policy
            } else if let raw = orderingTable["unpinned-apps"] {
                throw ConfigError.invalidValue(key: "ordering.unpinned-apps", expected: "append|ignore", actual: renderedValue(raw))
            }

            ordering.fixedApps = dedupe(try parseStringArrayIfPresent(table: orderingTable, key: "fixed-apps", section: "ordering", defaultValue: ordering.fixedApps))
            ordering.pinnedApps = dedupe(try parseStringArrayIfPresent(table: orderingTable, key: "pinned-apps", section: "ordering", defaultValue: ordering.pinnedApps))
        }

        if let filtersTable = table["filters"]?.table {
            logUnknownKeys(in: filtersTable, section: "filters", known: [
                "exclude-apps", "exclude-bundle-ids",
            ])
            filters.excludeApps = dedupe(try parseStringArrayIfPresent(table: filtersTable, key: "exclude-apps", section: "filters", defaultValue: filters.excludeApps))
            filters.excludeBundleIds = dedupe(try parseStringArrayIfPresent(table: filtersTable, key: "exclude-bundle-ids", section: "filters", defaultValue: filters.excludeBundleIds))
        }

        if let appearanceTable = table["appearance"]?.table {
            logUnknownKeys(in: appearanceTable, section: "appearance", known: [
                "theme", "icon-size", "item-padding", "item-spacing", "show-window-count",
            ])

            if let themeRaw = appearanceTable["theme"]?.string {
                guard let theme = ThemeMode(rawValue: themeRaw) else {
                    throw ConfigError.invalidValue(key: "appearance.theme", expected: "light|dark|system", actual: themeRaw)
                }
                appearance.theme = theme
            } else if let raw = appearanceTable["theme"] {
                throw ConfigError.invalidValue(key: "appearance.theme", expected: "light|dark|system", actual: renderedValue(raw))
            }

            appearance.iconSize = try parseIntIfPresent(table: appearanceTable, key: "icon-size", section: "appearance", defaultValue: appearance.iconSize)
            appearance.itemPadding = try parseIntIfPresent(table: appearanceTable, key: "item-padding", section: "appearance", defaultValue: appearance.itemPadding)
            appearance.itemSpacing = try parseIntIfPresent(table: appearanceTable, key: "item-spacing", section: "appearance", defaultValue: appearance.itemSpacing)
            appearance.showWindowCount = try parseBoolIfPresent(table: appearanceTable, key: "show-window-count", section: "appearance", defaultValue: appearance.showWindowCount)
        }

        if let performanceTable = table["performance"]?.table {
            logUnknownKeys(in: performanceTable, section: "performance", known: [
                "idle-cache-refresh", "log-level", "log-color",
            ])

            if let modeRaw = performanceTable["idle-cache-refresh"]?.string {
                guard let mode = IdleCacheRefreshMode(rawValue: modeRaw) else {
                    throw ConfigError.invalidValue(key: "performance.idle-cache-refresh", expected: "event-driven|interval", actual: modeRaw)
                }
                performance.idleCacheRefresh = mode
            } else if let raw = performanceTable["idle-cache-refresh"] {
                throw ConfigError.invalidValue(key: "performance.idle-cache-refresh", expected: "event-driven|interval", actual: renderedValue(raw))
            }

            if let logRaw = performanceTable["log-level"]?.string {
                guard let level = LogLevel(rawValue: logRaw) else {
                    throw ConfigError.invalidValue(key: "performance.log-level", expected: "debug|info|error", actual: logRaw)
                }
                performance.logLevel = level
            } else if let raw = performanceTable["log-level"] {
                throw ConfigError.invalidValue(key: "performance.log-level", expected: "debug|info|error", actual: renderedValue(raw))
            }

            if let colorRaw = performanceTable["log-color"]?.string {
                guard let color = LogColorMode(rawValue: colorRaw) else {
                    throw ConfigError.invalidValue(key: "performance.log-color", expected: "auto|always|never", actual: colorRaw)
                }
                performance.logColor = color
            } else if let raw = performanceTable["log-color"] {
                throw ConfigError.invalidValue(key: "performance.log-color", expected: "auto|always|never", actual: renderedValue(raw))
            }
        }

        let config = TabConfig(
            activation: activation,
            directional: directional,
            visibility: visibility,
            ordering: ordering,
            filters: filters,
            appearance: appearance,
            performance: performance
        )

        try ConfigValidation.validate(config)
        return config
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
                throw ConfigError.invalidValue(key: "\(section).\(key)", expected: "array of strings", actual: renderedValue(element))
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

    private static func logUnknownKeys(in table: TOMLTable, section: String, known: Set<String>) {
        let unknown = table.keys.filter { !known.contains($0) }.sorted()
        for key in unknown {
            Logger.info(.config, "Unknown key ignored: [\(section)].\(key)")
        }
    }
}
