@testable import TabCore
import AppKit
import Carbon
import XCTest

@MainActor
final class TabRuntimeTests: XCTestCase {
    func testRuntimeCanInitializeAndStop() {
        let runtime = TabRuntime(configURL: nil)
        runtime.stop()
    }

    func testRightArrowWithCmdAndActiveSessionRoutesRight() {
        let direction = CycleKeyRouter.routeDirection(
            keyCode: UInt16(kVK_RightArrow),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertEqual(direction, .right)
    }

    func testLeftArrowWithCmdAndActiveSessionRoutesLeft() {
        let direction = CycleKeyRouter.routeDirection(
            keyCode: UInt16(kVK_LeftArrow),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertEqual(direction, .left)
    }

    func testArrowWithoutActiveSessionIsIgnored() {
        let direction = CycleKeyRouter.routeDirection(
            keyCode: UInt16(kVK_RightArrow),
            flags: [.command],
            cycleActive: false
        )

        XCTAssertNil(direction)
    }

    func testArrowWithoutCmdIsIgnored() {
        let direction = CycleKeyRouter.routeDirection(
            keyCode: UInt16(kVK_RightArrow),
            flags: [],
            cycleActive: true
        )

        XCTAssertNil(direction)
    }

    func testNonArrowKeysAreIgnored() {
        let direction = CycleKeyRouter.routeDirection(
            keyCode: UInt16(kVK_Tab),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertNil(direction)
    }
}
