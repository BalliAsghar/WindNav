import Carbon
import Foundation

enum ModifierTabTriggerParserError: LocalizedError {
    case mustUseTab(String)
    case requiresModifier(String)

    var errorDescription: String? {
        switch self {
            case .mustUseTab(let raw):
                return "Invalid hud-trigger hotkey: '\(raw)'. Expected Modifier+Tab."
            case .requiresModifier(let raw):
                return "Invalid hud-trigger hotkey: '\(raw)'. At least one modifier is required."
        }
    }
}

enum ModifierTabTriggerParser {
    static func parse(_ raw: String) throws -> ParsedHotkey {
        let parsed = try HotkeyParser.parse(raw)
        guard parsed.keyCode == UInt32(kVK_Tab) else {
            throw ModifierTabTriggerParserError.mustUseTab(raw)
        }
        guard parsed.modifiers != 0 else {
            throw ModifierTabTriggerParserError.requiresModifier(raw)
        }
        return parsed
    }
}
