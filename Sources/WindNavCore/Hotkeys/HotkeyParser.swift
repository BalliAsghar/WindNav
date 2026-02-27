import Carbon
import Foundation

struct ParsedHotkey: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum HotkeyParserError: LocalizedError {
    case invalidFormat(String)
    case invalidModifier(String)
    case invalidKey(String)

    var errorDescription: String? {
        switch self {
            case .invalidFormat(let raw):
                return "Invalid hotkey format: '\(raw)'"
            case .invalidModifier(let raw):
                return "Invalid hotkey modifier: '\(raw)'"
            case .invalidKey(let raw):
                return "Invalid hotkey key: '\(raw)'"
        }
    }
}

enum HotkeyParser {
    static func parse(_ raw: String) throws -> ParsedHotkey {
        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let parts = normalized.split(separator: "-").map(String.init)
        guard parts.count >= 2, let keyRaw = parts.last else {
            throw HotkeyParserError.invalidFormat(raw)
        }

        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            guard let mask = modifierMaskByToken[modifier] else {
                throw HotkeyParserError.invalidModifier(modifier)
            }
            modifiers |= mask
        }

        guard let keyCode = keyCodeByToken[keyRaw] else {
            throw HotkeyParserError.invalidKey(keyRaw)
        }

        return ParsedHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private static let keyCodeByToken: [String: UInt32] = {
        var map: [String: UInt32] = [
            "left": UInt32(kVK_LeftArrow),
            "right": UInt32(kVK_RightArrow),
            "up": UInt32(kVK_UpArrow),
            "down": UInt32(kVK_DownArrow),
            "space": UInt32(kVK_Space),
            "return": UInt32(kVK_Return),
            "enter": UInt32(kVK_Return),
            "escape": UInt32(kVK_Escape),
            "tab": UInt32(kVK_Tab),
        ]

        let letterCodes: [String: Int] = [
            "a": kVK_ANSI_A,
            "b": kVK_ANSI_B,
            "c": kVK_ANSI_C,
            "d": kVK_ANSI_D,
            "e": kVK_ANSI_E,
            "f": kVK_ANSI_F,
            "g": kVK_ANSI_G,
            "h": kVK_ANSI_H,
            "i": kVK_ANSI_I,
            "j": kVK_ANSI_J,
            "k": kVK_ANSI_K,
            "l": kVK_ANSI_L,
            "m": kVK_ANSI_M,
            "n": kVK_ANSI_N,
            "o": kVK_ANSI_O,
            "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q,
            "r": kVK_ANSI_R,
            "s": kVK_ANSI_S,
            "t": kVK_ANSI_T,
            "u": kVK_ANSI_U,
            "v": kVK_ANSI_V,
            "w": kVK_ANSI_W,
            "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
        ]
        for (k, v) in letterCodes {
            map[k] = UInt32(v)
        }

        let numberCodes: [String: Int] = [
            "0": kVK_ANSI_0,
            "1": kVK_ANSI_1,
            "2": kVK_ANSI_2,
            "3": kVK_ANSI_3,
            "4": kVK_ANSI_4,
            "5": kVK_ANSI_5,
            "6": kVK_ANSI_6,
            "7": kVK_ANSI_7,
            "8": kVK_ANSI_8,
            "9": kVK_ANSI_9,
        ]
        for (k, v) in numberCodes {
            map[k] = UInt32(v)
        }

        return map
    }()

    private static let modifierMaskByToken: [String: UInt32] = [
        "cmd": UInt32(cmdKey),
        "command": UInt32(cmdKey),
        "ctrl": UInt32(controlKey),
        "control": UInt32(controlKey),
        "ctl": UInt32(controlKey),
        "opt": UInt32(optionKey),
        "option": UInt32(optionKey),
        "alt": UInt32(optionKey),
        "shift": UInt32(shiftKey),
    ]
}
