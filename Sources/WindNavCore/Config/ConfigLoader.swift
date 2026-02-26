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

        if let hotkeysTable = table["hotkeys"]?.table {
            hotkeys.focusLeft = hotkeysTable["focus-left"]?.string ?? hotkeys.focusLeft
            hotkeys.focusRight = hotkeysTable["focus-right"]?.string ?? hotkeys.focusRight
            Self.logIgnoredRemovedKeys([
                hotkeysTable["focus-up"] != nil ? "hotkeys.focus-up" : nil,
                hotkeysTable["focus-down"] != nil ? "hotkeys.focus-down" : nil,
            ])
        }

        if let navTable = table["navigation"]?.table {
            Self.logIgnoredRemovedKeys([
                navTable["scope"] != nil ? "navigation.scope" : nil,
                navTable["no-candidate"] != nil ? "navigation.no-candidate" : nil,
                navTable["filtering"] != nil ? "navigation.filtering" : nil,
            ])
            if let policyRaw = navTable["policy"]?.string {
                if policyRaw == "natural" {
                    Logger.info(.config, "Deprecated navigation.policy='natural' treated as 'mru-cycle'")
                    navigation.policy = .mruCycle
                } else if let value = NavigationPolicy(rawValue: policyRaw) {
                    navigation.policy = value
                } else {
                    throw ConfigError.invalidValue(
                        key: "navigation.policy",
                        expected: "mru-cycle|fixed-app-ring",
                        actual: policyRaw
                    )
                }
            }
            if let cycleTimeout = navTable["cycle-timeout-ms"]?.int {
                guard cycleTimeout > 0 else {
                    throw ConfigError.invalidValue(
                        key: "navigation.cycle-timeout-ms",
                        expected: "positive integer",
                        actual: "\(cycleTimeout)"
                    )
                }
                navigation.cycleTimeoutMs = cycleTimeout
            }

            if let fixedAppRingTable = navTable["fixed-app-ring"]?.table {
                if let pinnedAppsValue = fixedAppRingTable["pinned-apps"] {
                    guard let array = pinnedAppsValue.array else {
                        throw ConfigError.invalidValue(
                            key: "navigation.fixed-app-ring.pinned-apps",
                            expected: "array of strings",
                            actual: renderedValue(pinnedAppsValue)
                        )
                    }

                    var parsed: [String] = []
                    for element in array {
                        guard let string = element.string else {
                            throw ConfigError.invalidValue(
                                key: "navigation.fixed-app-ring.pinned-apps",
                                expected: "array of strings",
                                actual: renderedValue(pinnedAppsValue)
                            )
                        }
                        parsed.append(string)
                    }
                    navigation.fixedAppRing.pinnedApps = parsed
                }

                if let unpinnedRaw = fixedAppRingTable["unpinned-apps"]?.string {
                    guard let value = UnpinnedAppsPolicy(rawValue: unpinnedRaw) else {
                        throw ConfigError.invalidValue(
                            key: "navigation.fixed-app-ring.unpinned-apps",
                            expected: "append|ignore|alphabetical-tail",
                            actual: unpinnedRaw
                        )
                    }
                    navigation.fixedAppRing.unpinnedApps = value
                }

                if let inAppRaw = fixedAppRingTable["in-app-window"]?.string {
                    guard let value = InAppWindowSelectionPolicy(rawValue: inAppRaw) else {
                        throw ConfigError.invalidValue(
                            key: "navigation.fixed-app-ring.in-app-window",
                            expected: "last-focused|last-focused-on-monitor|spatial",
                            actual: inAppRaw
                        )
                    }
                    navigation.fixedAppRing.inAppWindow = value
                }

                if let groupingRaw = fixedAppRingTable["grouping"]?.string {
                    guard let value = GroupingMode(rawValue: groupingRaw) else {
                        throw ConfigError.invalidValue(
                            key: "navigation.fixed-app-ring.grouping",
                            expected: "one-stop-per-app",
                            actual: groupingRaw
                        )
                    }
                    navigation.fixedAppRing.grouping = value
                }
            }
        }

        if let loggingTable = table["logging"]?.table {
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

            if let hideDelay = hudTable["hide-delay-ms"]?.int {
                guard hideDelay > 0 else {
                    throw ConfigError.invalidValue(
                        key: "hud.hide-delay-ms",
                        expected: "positive integer",
                        actual: "\(hideDelay)"
                    )
                }
                hud.hideDelayMs = hideDelay
            } else if let raw = hudTable["hide-delay-ms"] {
                throw ConfigError.invalidValue(
                    key: "hud.hide-delay-ms",
                    expected: "positive integer",
                    actual: renderedValue(raw)
                )
            }

            Self.logIgnoredRemovedKeys([
                hudTable["show-window-count"] != nil ? "hud.show-window-count" : nil,
            ])

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

    private static func logIgnoredRemovedKeys(_ keys: [String?]) {
        let present = keys.compactMap { $0 }
        guard !present.isEmpty else { return }
        let rendered = present.joined(separator: ", ")
        Logger.info(.config, "Ignoring removed config key(s): \(rendered)")
    }
}
