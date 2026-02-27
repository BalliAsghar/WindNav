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

    func loadOrCreate() throws -> WindNavConfig {
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
                try WindNavConfig.defaultToml.write(to: configURL, atomically: true, encoding: .utf8)
            }
        } catch {
            throw ConfigError.io(error.localizedDescription)
        }
    }

    static func parse(_ text: String) throws -> WindNavConfig {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: text)
        } catch let parse as TOMLParseError {
            throw ConfigError.invalidToml(parse.debugDescription)
        } catch {
            throw ConfigError.invalidToml(error.localizedDescription)
        }

        var hotkeys = HotkeysConfig.default
        var navigation = NavigationConfig.default
        var logging = LoggingConfig.default
        var startup = StartupConfig.default
        var hud = HUDConfig.default

        Self.logUnknownKeys(in: table, section: "root", known: ["hotkeys", "navigation", "logging", "startup", "hud"])

        if let hotkeysTable = table["hotkeys"]?.table {
            Self.logUnknownKeys(in: hotkeysTable, section: "hotkeys", known: ["focus-left", "focus-right", "focus-up", "focus-down"])
            hotkeys.focusLeft = hotkeysTable["focus-left"]?.string ?? hotkeys.focusLeft
            hotkeys.focusRight = hotkeysTable["focus-right"]?.string ?? hotkeys.focusRight
            hotkeys.focusUp = hotkeysTable["focus-up"]?.string ?? hotkeys.focusUp
            hotkeys.focusDown = hotkeysTable["focus-down"]?.string ?? hotkeys.focusDown
        }

        if let navTable = table["navigation"]?.table {
            if let legacyPolicy = navTable["policy"] {
                throw ConfigError.invalidValue(
                    key: "navigation.policy",
                    expected: "removed; use navigation.mode = \"standard\"",
                    actual: renderedValue(legacyPolicy)
                )
            }
            if let legacyTable = navTable["fixed-app-ring"] {
                throw ConfigError.invalidValue(
                    key: "navigation.fixed-app-ring",
                    expected: "removed; use [navigation.standard]",
                    actual: renderedValue(legacyTable)
                )
            }

            Self.logUnknownKeys(
                in: navTable,
                section: "navigation",
                known: ["mode", "cycle-timeout-ms", "include-minimized", "include-hidden-apps", "standard"]
            )
            if let modeValue = navTable["mode"] {
                guard let modeRaw = modeValue.string else {
                    throw ConfigError.invalidValue(
                        key: "navigation.mode",
                        expected: "standard",
                        actual: renderedValue(modeValue)
                    )
                }
                guard let value = NavigationMode(rawValue: modeRaw) else {
                    throw ConfigError.invalidValue(
                        key: "navigation.mode",
                        expected: "standard",
                        actual: modeRaw
                    )
                }
                navigation.mode = value
            }
            if let cycleTimeout = navTable["cycle-timeout-ms"]?.int {
                guard cycleTimeout >= 0 else {
                    throw ConfigError.invalidValue(
                        key: "navigation.cycle-timeout-ms",
                        expected: "non-negative integer",
                        actual: "\(cycleTimeout)"
                    )
                }
                navigation.cycleTimeoutMs = cycleTimeout
            }
            if let includeMinimizedValue = navTable["include-minimized"] {
                guard let includeMinimized = includeMinimizedValue.bool else {
                    throw ConfigError.invalidValue(
                        key: "navigation.include-minimized",
                        expected: "true|false",
                        actual: renderedValue(includeMinimizedValue)
                    )
                }
                navigation.includeMinimized = includeMinimized
            }
            if let includeHiddenAppsValue = navTable["include-hidden-apps"] {
                guard let includeHiddenApps = includeHiddenAppsValue.bool else {
                    throw ConfigError.invalidValue(
                        key: "navigation.include-hidden-apps",
                        expected: "true|false",
                        actual: renderedValue(includeHiddenAppsValue)
                    )
                }
                navigation.includeHiddenApps = includeHiddenApps
            }

            if let standardTable = navTable["standard"]?.table {
                Self.logUnknownKeys(
                    in: standardTable,
                    section: "navigation.standard",
                    known: ["pinned-apps", "unpinned-apps", "in-app-window", "grouping"]
                )
                if let pinnedAppsValue = standardTable["pinned-apps"] {
                    guard let array = pinnedAppsValue.array else {
                        throw ConfigError.invalidValue(
                            key: "navigation.standard.pinned-apps",
                            expected: "array of strings",
                            actual: renderedValue(pinnedAppsValue)
                        )
                    }

                    var parsed: [String] = []
                    for element in array {
                        guard let string = element.string else {
                            throw ConfigError.invalidValue(
                                key: "navigation.standard.pinned-apps",
                                expected: "array of strings",
                                actual: renderedValue(pinnedAppsValue)
                            )
                        }
                        parsed.append(string)
                    }
                    navigation.fixedAppRing.pinnedApps = parsed
                }

                if let unpinnedRaw = standardTable["unpinned-apps"]?.string {
                    guard let value = UnpinnedAppsPolicy(rawValue: unpinnedRaw) else {
                        throw ConfigError.invalidValue(
                            key: "navigation.standard.unpinned-apps",
                            expected: "append|ignore",
                            actual: unpinnedRaw
                        )
                    }
                    navigation.fixedAppRing.unpinnedApps = value
                }

                if let inAppRaw = standardTable["in-app-window"]?.string {
                    guard let value = InAppWindowSelectionPolicy(rawValue: inAppRaw) else {
                        throw ConfigError.invalidValue(
                            key: "navigation.standard.in-app-window",
                            expected: "last-focused|last-focused-on-monitor|spatial",
                            actual: inAppRaw
                        )
                    }
                    navigation.fixedAppRing.inAppWindow = value
                }

                if let groupingRaw = standardTable["grouping"]?.string {
                    guard let value = GroupingMode(rawValue: groupingRaw) else {
                        throw ConfigError.invalidValue(
                            key: "navigation.standard.grouping",
                            expected: "one-stop-per-app",
                            actual: groupingRaw
                        )
                    }
                    navigation.fixedAppRing.grouping = value
                }
            }
        }

        if let loggingTable = table["logging"]?.table {
            Self.logUnknownKeys(in: loggingTable, section: "logging", known: ["level", "color"])
            if let levelRaw = loggingTable["level"]?.string {
                guard let value = LogLevel(rawValue: levelRaw) else {
                    throw ConfigError.invalidValue(key: "logging.level", expected: "info|error", actual: levelRaw)
                }
                logging.level = value
            }

            if let colorRaw = loggingTable["color"]?.string {
                guard let value = LogColorMode(rawValue: colorRaw) else {
                    throw ConfigError.invalidValue(key: "logging.color", expected: "auto|always|never", actual: colorRaw)
                }
                logging.color = value
            }
        }

        if let startupTable = table["startup"]?.table {
            Self.logUnknownKeys(in: startupTable, section: "startup", known: ["launch-on-login"])
            if let launchOnLoginValue = startupTable["launch-on-login"] {
                guard let launchOnLogin = launchOnLoginValue.bool else {
                    throw ConfigError.invalidValue(
                        key: "startup.launch-on-login",
                        expected: "true|false",
                        actual: renderedValue(launchOnLoginValue)
                    )
                }
                startup.launchOnLogin = launchOnLogin
            }
        }

        if let hudTable = table["hud"]?.table {
            Self.logUnknownKeys(in: hudTable, section: "hud", known: ["enabled", "show-icons", "icon-size", "position"])
            if let enabled = hudTable["enabled"]?.bool {
                hud.enabled = enabled
            } else if let raw = hudTable["enabled"] {
                throw ConfigError.invalidValue(
                    key: "hud.enabled",
                    expected: "true|false",
                    actual: renderedValue(raw)
                )
            }

            if let showIcons = hudTable["show-icons"]?.bool {
                hud.showIcons = showIcons
            } else if let raw = hudTable["show-icons"] {
                throw ConfigError.invalidValue(
                    key: "hud.show-icons",
                    expected: "true|false",
                    actual: renderedValue(raw)
                )
            }

            if let iconSize = hudTable["icon-size"]?.int {
                guard iconSize > 0 else {
                    throw ConfigError.invalidValue(
                        key: "hud.icon-size",
                        expected: "positive integer pixels",
                        actual: "\(iconSize)"
                    )
                }
                hud.iconSize = iconSize
            } else if let raw = hudTable["icon-size"] {
                throw ConfigError.invalidValue(
                    key: "hud.icon-size",
                    expected: "positive integer pixels",
                    actual: renderedValue(raw)
                )
            }

            if let positionRaw = hudTable["position"]?.string {
                guard let value = HUDPosition(rawValue: positionRaw) else {
                    throw ConfigError.invalidValue(
                        key: "hud.position",
                        expected: "top-center|middle-center|bottom-center",
                        actual: positionRaw
                    )
                }
                hud.position = value
            }
        }

        return WindNavConfig(hotkeys: hotkeys, navigation: navigation, logging: logging, startup: startup, hud: hud)
    }

    private static func renderedValue(_ value: any TOMLValueConvertible) -> String {
        String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func logUnknownKeys(in table: TOMLTable, section: String, known: Set<String>) {
        let unknown = table.keys.filter { !known.contains($0) }.sorted()
        for key in unknown {
            Logger.info(.config, "Unknown Key: [\(section)].\(key)")
        }
    }
}
