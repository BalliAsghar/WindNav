@testable import TabCore
import XCTest

final class MinimalHUDControllerTests: XCTestCase {
    func testRenderItemShowsWindowIndexText() {
        XCTAssertEqual(HUDBadgeFormatter.badgeText(for: 1), "1")
        XCTAssertEqual(HUDBadgeFormatter.badgeText(for: 2), "2")
        XCTAssertEqual(HUDBadgeFormatter.badgeText(for: 10), "10")
    }

    func testRenderItemOmitsBadgeWhenIndexIsNilOrInvalid() {
        XCTAssertNil(HUDBadgeFormatter.badgeText(for: nil))
        XCTAssertNil(HUDBadgeFormatter.badgeText(for: 0))
    }
}
