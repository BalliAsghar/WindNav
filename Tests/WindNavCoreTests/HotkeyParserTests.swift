@testable import WindNavCore
import Carbon
import XCTest

final class HotkeyParserTests: XCTestCase {
    func testParsesCmdArrow() throws {
        let parsed = try HotkeyParser.parse("cmd-left")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_LeftArrow))
        XCTAssertEqual(parsed.modifiers, UInt32(cmdKey))
    }

    func testParsesOptionShortAlias() throws {
        let parsed = try HotkeyParser.parse("opt-right")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_RightArrow))
        XCTAssertEqual(parsed.modifiers, UInt32(optionKey))
    }

    func testParsesFullModifierNames() throws {
        let parsed = try HotkeyParser.parse("command-control-option-up")
        let expected = UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_UpArrow))
        XCTAssertEqual(parsed.modifiers, expected)
    }

    func testParsesCtlAlias() throws {
        let parsed = try HotkeyParser.parse("ctl-down")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_DownArrow))
        XCTAssertEqual(parsed.modifiers, UInt32(controlKey))
    }

    func testParsesMixedMultipleModifiers() throws {
        let parsed = try HotkeyParser.parse("cmd-opt-shift-left")
        let expected = UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey)
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_LeftArrow))
        XCTAssertEqual(parsed.modifiers, expected)
    }

    func testParsesLegacyAltAlias() throws {
        let parsed = try HotkeyParser.parse("alt-down")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_DownArrow))
        XCTAssertEqual(parsed.modifiers, UInt32(optionKey))
    }

    func testRejectsInvalidKey() {
        XCTAssertThrowsError(try HotkeyParser.parse("cmd-notakey"))
    }

    func testRejectsInvalidModifier() {
        XCTAssertThrowsError(try HotkeyParser.parse("meta-left"))
    }

    func testRejectsMissingModifierFormat() {
        XCTAssertThrowsError(try HotkeyParser.parse("left"))
    }
}
