@testable import TabCore
import Carbon
import XCTest

final class HotkeyParserTests: XCTestCase {
    func testParsesCmdTab() throws {
        let parsed = try HotkeyParser.parse("cmd-tab")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_Tab))
        XCTAssertEqual(parsed.modifiers, UInt32(cmdKey))
    }

    func testParsesOptCmdH() throws {
        let parsed = try HotkeyParser.parse("opt-cmd-h")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_ANSI_H))
        XCTAssertEqual(parsed.modifiers, UInt32(optionKey | cmdKey))
    }

    func testInvalidFormatThrows() {
        XCTAssertThrowsError(try HotkeyParser.parse("cmd"))
    }

    func testInvalidKeyThrows() {
        XCTAssertThrowsError(try HotkeyParser.parse("cmd-nonesuch"))
    }

    func testStaticDirectionIdMapping() {
        XCTAssertEqual(CarbonHotkeyRegistrar.hotkeyID(for: .activationForward), 1)
        XCTAssertEqual(CarbonHotkeyRegistrar.hotkeyID(for: .activationBackward), 2)
        XCTAssertEqual(CarbonHotkeyRegistrar.hotkeyID(for: .directionalLeft), 3)
        XCTAssertEqual(CarbonHotkeyRegistrar.action(forHotkeyID: 4), .directionalRight)
        XCTAssertNil(CarbonHotkeyRegistrar.action(forHotkeyID: 999))
    }
}
