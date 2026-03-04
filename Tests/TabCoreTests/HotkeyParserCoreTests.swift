@testable import TabCore
import Carbon
import XCTest

final class HotkeyParserCoreTests: XCTestCase {
    func testParsesCmdTab() throws {
        let parsed = try HotkeyParser.parse("cmd-tab")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_Tab))
        XCTAssertEqual(parsed.modifiers, UInt32(cmdKey))
    }

    func testInvalidFormatThrows() {
        XCTAssertThrowsError(try HotkeyParser.parse("tab"))
    }
}
