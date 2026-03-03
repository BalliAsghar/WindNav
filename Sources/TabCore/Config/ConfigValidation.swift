import Foundation

enum ConfigValidation {
    static func validate(_ config: TabConfig) throws {
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
    }
}
