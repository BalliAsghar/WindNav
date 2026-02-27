@testable import WindNavCore
import Carbon
import XCTest

final class ModifierTabTriggerParserTests: XCTestCase {
    func testAcceptsModifierTabHotkey() throws {
        let parsed = try ModifierTabTriggerParser.parse("cmd-tab")
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_Tab))
        XCTAssertNotEqual(parsed.modifiers, 0)
    }

    func testRejectsNonTabKey() {
        XCTAssertThrowsError(try ModifierTabTriggerParser.parse("cmd-right"))
    }

    func testRejectsMissingModifier() {
        XCTAssertThrowsError(try ModifierTabTriggerParser.parse("tab"))
    }
}
