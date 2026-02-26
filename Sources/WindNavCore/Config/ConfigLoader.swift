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

        if let hotkeysTable = table["hotkeys"]?.table {
            hotkeys.focusLeft = hotkeysTable["focus-left"]?.string ?? hotkeys.focusLeft
            hotkeys.focusRight = hotkeysTable["focus-right"]?.string ?? hotkeys.focusRight
            if hotkeysTable["focus-up"] != nil || hotkeysTable["focus-down"] != nil {
                Logger.info(.config, "Ignoring deprecated hotkeys focus-up/focus-down (up/down are unsupported)")
            }
        }

        if let navTable = table["navigation"]?.table {
            if let scopeRaw = navTable["scope"]?.string {
                guard let value = NavigationScope(rawValue: scopeRaw) else {
                    throw ConfigError.invalidValue(key: "navigation.scope", expected: "current-monitor", actual: scopeRaw)
                }
                navigation.scope = value
            }
            if let policyRaw = navTable["policy"]?.string {
                if policyRaw == "natural" {
                    Logger.info(.config, "Deprecated navigation.policy='natural' treated as 'mru-cycle'")
                    navigation.policy = .mruCycle
                } else if let value = NavigationPolicy(rawValue: policyRaw) {
                    navigation.policy = value
                } else {
                    throw ConfigError.invalidValue(key: "navigation.policy", expected: "mru-cycle", actual: policyRaw)
                }
            }
            if let behaviorRaw = navTable["no-candidate"]?.string {
                guard let value = NoCandidateBehavior(rawValue: behaviorRaw) else {
                    throw ConfigError.invalidValue(key: "navigation.no-candidate", expected: "noop", actual: behaviorRaw)
                }
                navigation.noCandidate = value
            }
            if let filteringRaw = navTable["filtering"]?.string {
                guard let value = FilteringMode(rawValue: filteringRaw) else {
                    throw ConfigError.invalidValue(key: "navigation.filtering", expected: "conservative", actual: filteringRaw)
                }
                navigation.filtering = value
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

        return WindNavConfig(hotkeys: hotkeys, navigation: navigation, logging: logging)
    }
}
