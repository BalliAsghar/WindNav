@testable import WindNavCore
import Carbon
import XCTest

final class HotkeyParserTests: XCTestCase {
    func testParsesCmdArrow() throws {
        let parsed = try HotkeyParser.parse("cmd-left")
        XCTAssertEqual(parsed.keyCode, 123)
    }

    func testRejectsInvalidKey() {
        XCTAssertThrowsError(try HotkeyParser.parse("cmd-notakey"))
    }

    func testParsesTabKey() throws {
        let parsed = try HotkeyParser.parse("cmd-tab")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_Tab))
    }
}
